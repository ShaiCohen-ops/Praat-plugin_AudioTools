# ============================================================
# Praat AudioTools - Neural_Phonetic_Speed_Mapper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Phonetic Speed Mapper - Applies different time stretch
#   factors to different phonetic categories using FFNet classification.
#
# Changelog v0.3:
#   - Fixed preset comparison (number not string)
#   - Fixed Get total costs selection
#   - Added preset name to output
#   - Added visualization
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

form Neural Phonetic Speed Mapper v0.3
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Speech Clarity
        option Vowel Stretch
        option Consonant Emphasis
        option Time Compress
        option Dreamy Slow
        option Rhythmic Stutter
        option Fast Forward
    comment === Stretch Factors (>1 = longer, <1 = shorter) ===
    positive Vowel_stretch 0.5
    positive Consonant_stretch 2.0
    positive Other_stretch 0.8
    positive Silence_stretch 1.0
    comment === Processing ===
    positive Smoothing_ms 20
    positive Temperature 0.4
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Speech Clarity
    vowel_stretch = 1.3
    consonant_stretch = 1.8
    other_stretch = 1.2
    silence_stretch = 0.8
    smoothing_ms = 25
    temperature = 0.35
    presetName$ = "SpeechClarity"
elsif preset = 3
    # Vowel Stretch
    vowel_stretch = 2.0
    consonant_stretch = 1.0
    other_stretch = 1.2
    silence_stretch = 1.0
    smoothing_ms = 30
    temperature = 0.3
    presetName$ = "VowelStretch"
elsif preset = 4
    # Consonant Emphasis
    vowel_stretch = 0.8
    consonant_stretch = 2.5
    other_stretch = 1.5
    silence_stretch = 0.7
    smoothing_ms = 15
    temperature = 0.4
    presetName$ = "ConsonantEmphasis"
elsif preset = 5
    # Time Compress
    vowel_stretch = 0.6
    consonant_stretch = 0.7
    other_stretch = 0.65
    silence_stretch = 0.3
    smoothing_ms = 20
    temperature = 0.5
    presetName$ = "TimeCompress"
elsif preset = 6
    # Dreamy Slow
    vowel_stretch = 2.5
    consonant_stretch = 1.5
    other_stretch = 2.0
    silence_stretch = 1.8
    smoothing_ms = 40
    temperature = 0.25
    presetName$ = "DreamySlow"
elsif preset = 7
    # Rhythmic Stutter
    vowel_stretch = 0.4
    consonant_stretch = 3.0
    other_stretch = 0.5
    silence_stretch = 2.0
    smoothing_ms = 10
    temperature = 0.5
    presetName$ = "RhythmicStutter"
elsif preset = 8
    # Fast Forward
    vowel_stretch = 0.5
    consonant_stretch = 0.5
    other_stretch = 0.5
    silence_stretch = 0.2
    smoothing_ms = 15
    temperature = 0.4
    presetName$ = "FastForward"
else
    presetName$ = "Manual"
endif

# Hidden parameters
frame_step_sec = 0.005
hidden_units = 16
training_iterations = 800
learning_rate = 0.001
vowel_hnr_threshold = 5.0
fricative_hnr_max = 3.0
silence_threshold = 45

# ============================================
# SETUP
# ============================================

selectObject: sound
duration = Get total duration
fs = Get sampling frequency

if duration < 0.1
    exitScript: "Sound too short (minimum 0.1 seconds)."
endif

clearinfo
writeInfoLine: "=== Neural Phonetic Speed Mapper v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Vowel: ", vowel_stretch, "x | Consonant: ", consonant_stretch, "x"
appendInfoLine: "Other: ", other_stretch, "x | Silence: ", silence_stretch, "x"
appendInfoLine: ""

selectObject: sound
workSnd = Convert to mono
Rename: "Work"

# ============================================
# FEATURE EXTRACTION
# ============================================

appendInfoLine: "Analyzing phonetic features..."

nFrames = floor(duration / frame_step_sec)
if nFrames < 10
    nFrames = 10
endif

feat_mfcc_1# = zero#(nFrames)
feat_mfcc_2# = zero#(nFrames)
feat_mfcc_3# = zero#(nFrames)
feat_f1# = zero#(nFrames)
feat_f2# = zero#(nFrames)
feat_intensity# = zero#(nFrames)
feat_hnr# = zero#(nFrames)
feat_pitch# = zero#(nFrames)
frame_time# = zero#(nFrames)

cat_vowel# = zero#(nFrames)
cat_consonant# = zero#(nFrames)
cat_other# = zero#(nFrames)
cat_silence# = zero#(nFrames)

selectObject: workSnd
pitch_obj = To Pitch: 0, 75, 600

selectObject: workSnd
intensity_obj = To Intensity: 75, 0, "yes"

selectObject: workSnd
formant_obj = To Formant (burg): 0, 5, 5500, 0.025, 50

selectObject: workSnd
mfcc_obj = To MFCC: 12, 0.025, frame_step_sec, 100, 100, 0

selectObject: workSnd
hnr_obj = To Harmonicity (cc): frame_step_sec, 75, 0.1, 1.0

selectObject: mfcc_obj
nFrames_mfcc = Get number of frames

for i from 1 to nFrames
    t = (i - 0.5) * frame_step_sec
    frame_time#[i] = t
    
    iM = min(i, nFrames_mfcc)
    selectObject: mfcc_obj
    for c from 1 to 3
        v = Get value in frame: iM, c
        if v = undefined
            v = 0
        endif
        if c = 1
            feat_mfcc_1#[i] = v
        elsif c = 2
            feat_mfcc_2#[i] = v
        else
            feat_mfcc_3#[i] = v
        endif
    endfor
    
    selectObject: formant_obj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    if f1 = undefined
        f1 = 500
    endif
    if f2 = undefined
        f2 = 1500
    endif
    feat_f1#[i] = f1
    feat_f2#[i] = f2
    
    selectObject: intensity_obj
    iv = Get value at time: t, "cubic"
    if iv = undefined
        iv = 50
    endif
    feat_intensity#[i] = iv
    
    selectObject: hnr_obj
    hnr = Get value at time: t, "cubic"
    if hnr = undefined
        hnr = 0
    endif
    feat_hnr#[i] = hnr
    
    selectObject: pitch_obj
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        feat_pitch#[i] = 0
    else
        feat_pitch#[i] = f0
    endif
    
    # Classify
    if iv < silence_threshold
        cat_silence#[i] = 1
    elsif hnr > vowel_hnr_threshold and f0 > 0 and f1 > 300
        cat_vowel#[i] = 1
    elsif iv > silence_threshold and hnr < fricative_hnr_max and f0 <= 0
        cat_consonant#[i] = 1
    else
        cat_other#[i] = 1
    endif
endfor

removeObject: pitch_obj, intensity_obj, formant_obj, mfcc_obj, hnr_obj

appendInfoLine: "  ", nFrames, " frames analyzed"

# ============================================
# NORMALIZE FEATURES
# ============================================

appendInfoLine: "Normalizing features..."

# MFCC 1
min_v = feat_mfcc_1#[1]
max_v = feat_mfcc_1#[1]
for i from 2 to nFrames
    if feat_mfcc_1#[i] < min_v
        min_v = feat_mfcc_1#[i]
    endif
    if feat_mfcc_1#[i] > max_v
        max_v = feat_mfcc_1#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_mfcc_1#[i] = (feat_mfcc_1#[i] - min_v) / range
endfor

# MFCC 2
min_v = feat_mfcc_2#[1]
max_v = feat_mfcc_2#[1]
for i from 2 to nFrames
    if feat_mfcc_2#[i] < min_v
        min_v = feat_mfcc_2#[i]
    endif
    if feat_mfcc_2#[i] > max_v
        max_v = feat_mfcc_2#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_mfcc_2#[i] = (feat_mfcc_2#[i] - min_v) / range
endfor

# MFCC 3
min_v = feat_mfcc_3#[1]
max_v = feat_mfcc_3#[1]
for i from 2 to nFrames
    if feat_mfcc_3#[i] < min_v
        min_v = feat_mfcc_3#[i]
    endif
    if feat_mfcc_3#[i] > max_v
        max_v = feat_mfcc_3#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_mfcc_3#[i] = (feat_mfcc_3#[i] - min_v) / range
endfor

# F1
min_v = feat_f1#[1]
max_v = feat_f1#[1]
for i from 2 to nFrames
    if feat_f1#[i] < min_v
        min_v = feat_f1#[i]
    endif
    if feat_f1#[i] > max_v
        max_v = feat_f1#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_f1#[i] = (feat_f1#[i] - min_v) / range
endfor

# F2
min_v = feat_f2#[1]
max_v = feat_f2#[1]
for i from 2 to nFrames
    if feat_f2#[i] < min_v
        min_v = feat_f2#[i]
    endif
    if feat_f2#[i] > max_v
        max_v = feat_f2#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_f2#[i] = (feat_f2#[i] - min_v) / range
endfor

# Intensity
min_v = feat_intensity#[1]
max_v = feat_intensity#[1]
for i from 2 to nFrames
    if feat_intensity#[i] < min_v
        min_v = feat_intensity#[i]
    endif
    if feat_intensity#[i] > max_v
        max_v = feat_intensity#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_intensity#[i] = (feat_intensity#[i] - min_v) / range
endfor

# HNR
min_v = feat_hnr#[1]
max_v = feat_hnr#[1]
for i from 2 to nFrames
    if feat_hnr#[i] < min_v
        min_v = feat_hnr#[i]
    endif
    if feat_hnr#[i] > max_v
        max_v = feat_hnr#[i]
    endif
endfor
range = max_v - min_v
if range < 0.0001
    range = 1
endif
for i from 1 to nFrames
    feat_hnr#[i] = (feat_hnr#[i] - min_v) / range
endfor

# Pitch
max_pitch = 0
for i from 1 to nFrames
    if feat_pitch#[i] > max_pitch
        max_pitch = feat_pitch#[i]
    endif
endfor
if max_pitch < 1
    max_pitch = 600
endif
for i from 1 to nFrames
    if feat_pitch#[i] > 0
        feat_pitch#[i] = feat_pitch#[i] / max_pitch
        if feat_pitch#[i] > 1
            feat_pitch#[i] = 1
        endif
    endif
endfor

# Final clamp
for i from 1 to nFrames
    feat_mfcc_1#[i] = max(0, min(1, feat_mfcc_1#[i]))
    feat_mfcc_2#[i] = max(0, min(1, feat_mfcc_2#[i]))
    feat_mfcc_3#[i] = max(0, min(1, feat_mfcc_3#[i]))
    feat_f1#[i] = max(0, min(1, feat_f1#[i]))
    feat_f2#[i] = max(0, min(1, feat_f2#[i]))
    feat_intensity#[i] = max(0, min(1, feat_intensity#[i]))
    feat_hnr#[i] = max(0, min(1, feat_hnr#[i]))
    feat_pitch#[i] = max(0, min(1, feat_pitch#[i]))
endfor

# ============================================
# BUILD PATTERN AND TRAIN FFNET
# ============================================

appendInfoLine: "Training neural network..."

n_features = 8
Create TableOfReal: "Features", nFrames, n_features
feat_table = selected("TableOfReal")

for i from 1 to nFrames
    selectObject: feat_table
    Set value: i, 1, feat_mfcc_1#[i]
    Set value: i, 2, feat_mfcc_2#[i]
    Set value: i, 3, feat_mfcc_3#[i]
    Set value: i, 4, feat_f1#[i]
    Set value: i, 5, feat_f2#[i]
    Set value: i, 6, feat_intensity#[i]
    Set value: i, 7, feat_hnr#[i]
    Set value: i, 8, feat_pitch#[i]
endfor

selectObject: feat_table
To Matrix
feat_matrix = selected("Matrix")
To Pattern: 1
pattern = selected("PatternList")

selectObject: pattern
Formula: "if self < 0 then 0 else if self > 1 then 1 else self fi fi"

Create Categories: "Targets"
categories = selected("Categories")

for i from 1 to nFrames
    selectObject: categories
    if cat_vowel#[i] = 1
        Append category: "vowel"
    elsif cat_consonant#[i] = 1
        Append category: "consonant"
    elsif cat_silence#[i] = 1
        Append category: "silence"
    else
        Append category: "other"
    endif
endfor

selectObject: pattern
plusObject: categories
ffnet = To FFNet: hidden_units, 0

prev_cost = 1e9
stale = 0
iter = 0
chunk = 100

while iter < training_iterations
    selectObject: ffnet
    plusObject: pattern
    plusObject: categories
    Learn: chunk, learning_rate, "Minimum-squared-error"
    
    selectObject: ffnet
    plusObject: pattern
    plusObject: categories
    current_cost = Get total costs: "Minimum-squared-error"
    
    if abs(prev_cost - current_cost) < prev_cost * 0.001
        stale += 1
    else
        stale = 0
    endif
    
    prev_cost = current_cost
    iter += chunk
    
    if stale >= 5
        appendInfoLine: "  Converged at iteration ", iter
        iter = training_iterations + 1
    endif
endwhile

appendInfoLine: "  Training complete"

selectObject: ffnet
plusObject: pattern
To ActivationList: 1
activations = selected("Activation")
To Matrix
activation_matrix = selected("Matrix")

weight_vowel# = zero#(nFrames)
weight_consonant# = zero#(nFrames)
weight_other# = zero#(nFrames)
weight_silence# = zero#(nFrames)

for i from 1 to nFrames
    selectObject: activation_matrix
    a1 = Get value in cell: i, 1
    a2 = Get value in cell: i, 2
    a3 = Get value in cell: i, 3
    a4 = Get value in cell: i, 4
    
    t_div = max(0.001, temperature)
    max_a = max(a1, max(a2, max(a3, a4)))
    
    e1 = exp((a1 - max_a) / t_div)
    e2 = exp((a2 - max_a) / t_div)
    e3 = exp((a3 - max_a) / t_div)
    e4 = exp((a4 - max_a) / t_div)
    
    sum_e = e1 + e2 + e3 + e4
    if sum_e < 0.001
        sum_e = 1
    endif
    
    weight_vowel#[i] = e1 / sum_e
    weight_consonant#[i] = e2 / sum_e
    weight_other#[i] = e3 / sum_e
    weight_silence#[i] = e4 / sum_e
endfor

removeObject: feat_table, feat_matrix, pattern, categories, ffnet, activations, activation_matrix

# ============================================
# CALCULATE STRETCH FACTORS
# ============================================

appendInfoLine: "Calculating stretch factors..."

stretch_factor# = zero#(nFrames)

for i from 1 to nFrames
    factor = weight_vowel#[i] * vowel_stretch +
        ... weight_consonant#[i] * consonant_stretch +
        ... weight_other#[i] * other_stretch +
        ... weight_silence#[i] * silence_stretch
    
    factor = max(0.1, min(10, factor))
    stretch_factor#[i] = factor
endfor

# ============================================
# SMOOTH STRETCH FACTORS
# ============================================

smooth_frames = round(smoothing_ms / (frame_step_sec * 1000))
if smooth_frames < 1
    smooth_frames = 1
endif

stretch_smooth# = zero#(nFrames)

for i from 1 to nFrames
    i1 = max(1, i - smooth_frames)
    i2 = min(nFrames, i + smooth_frames)
    n = i2 - i1 + 1
    
    sum_s = 0
    for k from i1 to i2
        sum_s += stretch_factor#[k]
    endfor
    
    stretch_smooth#[i] = sum_s / n
endfor

# ============================================
# BUILD DURATION TIER
# ============================================

appendInfoLine: "Building duration tier..."

durationTier = Create DurationTier: "stretch", 0, duration

point_interval = 0.02
last_t = -1

selectObject: durationTier
Add point: 0, stretch_smooth#[1]

for i from 1 to nFrames
    t = frame_time#[i]
    
    if t - last_t >= point_interval
        dur_factor = stretch_smooth#[i]
        
        selectObject: durationTier
        Add point: t, dur_factor
        last_t = t
    endif
endfor

selectObject: durationTier
Add point: duration, stretch_smooth#[nFrames]

# ============================================
# RESYNTHESIS
# ============================================

appendInfoLine: "Resynthesizing..."

selectObject: workSnd
manip = To Manipulation: 0.01, 75, 600

selectObject: manip
plusObject: durationTier
Replace duration tier

selectObject: manip
finalOut = Get resynthesis (overlap-add)
Rename: sound_name$ + "_speedmap_" + presetName$
Scale peak: 0.99

# ============================================
# CLEANUP
# ============================================

removeObject: workSnd, manip, durationTier

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    selectObject: finalOut
    out_dur = Get total duration
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Neural Phonetic Speed Mapper: " + sound_name$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    Text top: "no", fixed$(duration, 2) + " s"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: finalOut
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text top: "no", fixed$(out_dur, 2) + " s (" + fixed$(out_dur/duration, 2) + "x)"
    
    # Phonetic weights
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.9, 3.9
    
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
    
    # Vowel (red)
    Colour: "{0.8, 0.3, 0.3}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_vowel#[i-1], t2, weight_vowel#[i]
    endfor
    
    # Consonant (blue)
    Colour: "{0.3, 0.4, 0.8}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_consonant#[i-1], t2, weight_consonant#[i]
    endfor
    
    # Other (green)
    Colour: "{0.4, 0.7, 0.4}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_other#[i-1], t2, weight_other#[i]
    endfor
    
    # Silence (gray)
    Colour: "{0.6, 0.6, 0.6}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_silence#[i-1], t2, weight_silence#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Weight"
    
    # Stretch factor
    Select outer viewport: 0, 8, 4.2, 5.4
    Select inner viewport: 0.6, 7.6, 4.4, 5.3
    
    maxStretch = 1
    minStretch = 1
    for i from 1 to nFrames
        if stretch_smooth#[i] > maxStretch
            maxStretch = stretch_smooth#[i]
        endif
        if stretch_smooth#[i] < minStretch
            minStretch = stretch_smooth#[i]
        endif
    endfor
    
    Axes: 0, duration, minStretch * 0.9, maxStretch * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minStretch * 0.9, maxStretch * 1.1
    
    # Reference line at 1.0
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 1, duration, 1
    Solid line
    
    # Stretch curve
    Colour: "{0.6, 0.3, 0.6}"
    Line width: 2
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, stretch_smooth#[i-1], t2, stretch_smooth#[i]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Stretch"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.5, 6.0
    Font size: 8
    Colour: "{0.8, 0.3, 0.3}"
    Text: 0.12, "centre", 0.5, "half", "— Vowel (" + fixed$(vowel_stretch, 1) + "x)"
    Colour: "{0.3, 0.4, 0.8}"
    Text: 0.32, "centre", 0.5, "half", "— Cons (" + fixed$(consonant_stretch, 1) + "x)"
    Colour: "{0.4, 0.7, 0.4}"
    Text: 0.52, "centre", 0.5, "half", "— Other (" + fixed$(other_stretch, 1) + "x)"
    Colour: "{0.6, 0.6, 0.6}"
    Text: 0.72, "centre", 0.5, "half", "— Silence (" + fixed$(silence_stretch, 1) + "x)"
    Colour: "{0.6, 0.3, 0.6}"
    Text: 0.9, "centre", 0.5, "half", "— Stretch"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================
# OUTPUT
# ============================================

selectObject: sound
plusObject: finalOut

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: finalOut
out_dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Original: ", fixed$(duration, 2), " s"
appendInfoLine: "New: ", fixed$(out_dur, 2), " s"
appendInfoLine: "Ratio: ", fixed$(out_dur / duration, 2), "x"

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut