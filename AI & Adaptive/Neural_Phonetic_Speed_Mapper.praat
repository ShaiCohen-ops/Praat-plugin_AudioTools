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
    vowel_stretch = 1.3
    consonant_stretch = 1.8
    other_stretch = 1.2
    silence_stretch = 0.8
    smoothing_ms = 25
    temperature = 0.35
    presetName$ = "SpeechClarity"
elsif preset = 3
    vowel_stretch = 2.0
    consonant_stretch = 1.0
    other_stretch = 1.2
    silence_stretch = 1.0
    smoothing_ms = 30
    temperature = 0.3
    presetName$ = "VowelStretch"
elsif preset = 4
    vowel_stretch = 0.8
    consonant_stretch = 2.5
    other_stretch = 1.5
    silence_stretch = 0.7
    smoothing_ms = 15
    temperature = 0.4
    presetName$ = "ConsonantEmphasis"
elsif preset = 5
    vowel_stretch = 0.6
    consonant_stretch = 0.7
    other_stretch = 0.65
    silence_stretch = 0.3
    smoothing_ms = 20
    temperature = 0.5
    presetName$ = "TimeCompress"
elsif preset = 6
    vowel_stretch = 2.5
    consonant_stretch = 1.5
    other_stretch = 2.0
    silence_stretch = 1.8
    smoothing_ms = 40
    temperature = 0.25
    presetName$ = "DreamySlow"
elsif preset = 7
    vowel_stretch = 0.4
    consonant_stretch = 3.0
    other_stretch = 0.5
    silence_stretch = 2.0
    smoothing_ms = 10
    temperature = 0.5
    presetName$ = "RhythmicStutter"
elsif preset = 8
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
silence_drop_db = 35
min_formant_valid_fraction = 0.15

# ============================================
# SETUP
# ============================================
selectObject: sound
duration = Get total duration
fs = Get sampling frequency
tmin = Get start time
tmax = Get end time
nChannels = Get number of channels
nyquist = fs / 2

if duration < 0.1
    exitScript: "Sound too short (minimum 0.1 seconds)."
endif

formant_ceiling = min(5500, nyquist - 100)
if formant_ceiling < 2200
    formant_ceiling = nyquist - 50
endif
if formant_ceiling <= 1000
    exitScript: "Sample rate is too low for reliable phonetic analysis."
endif

clearinfo
writeInfoLine: "=== Neural Phonetic Speed Mapper v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Vowel: ", vowel_stretch, "x | Consonant: ", consonant_stretch, "x"
appendInfoLine: "Other: ", other_stretch, "x | Silence: ", silence_stretch, "x"
appendInfoLine: ""

# Analysis/resynthesis remains mono, matching the original tool's behavior.
selectObject: sound
workSnd = Convert to mono
Rename: "Work"

# ============================================
# FEATURE EXTRACTION
# ============================================
appendInfoLine: "Analyzing phonetic features..."

selectObject: workSnd
pitch_obj = To Pitch: 0, 75, 600
selectObject: workSnd
intensity_obj = To Intensity: 75, 0, "yes"
selectObject: workSnd
formant_obj = To Formant (burg): 0, 5, formant_ceiling, 0.025, 50
selectObject: workSnd
mfcc_obj = To MFCC: 12, 0.025, frame_step_sec, 100, 100, 0
selectObject: workSnd
hnr_obj = To Harmonicity (cc): frame_step_sec, 75, 0.1, 1.0

selectObject: mfcc_obj
nFrames = Get number of frames
if nFrames < 1
    removeObject: pitch_obj, intensity_obj, formant_obj, mfcc_obj, hnr_obj, workSnd
    exitScript: "MFCC analysis produced no frames."
endif

feat_mfcc_1# = zero#(nFrames)
feat_mfcc_2# = zero#(nFrames)
feat_mfcc_3# = zero#(nFrames)
feat_f1# = zero#(nFrames)
feat_f2# = zero#(nFrames)
feat_formant_valid# = zero#(nFrames)
feat_intensity# = zero#(nFrames)
feat_hnr# = zero#(nFrames)
feat_pitch# = zero#(nFrames)
frame_time# = zero#(nFrames)

cat_vowel# = zero#(nFrames)
cat_consonant# = zero#(nFrames)
cat_other# = zero#(nFrames)
cat_silence# = zero#(nFrames)

# Relative silence threshold: stable under input gain changes.
selectObject: intensity_obj
intensityMax = Get maximum: 0, 0, "Parabolic"
if intensityMax = undefined
    intensityMax = 70
endif
silence_threshold = intensityMax - silence_drop_db

# Pass 1: structural formant validity + file-local fill statistics.
sumF1 = 0
sumF2 = 0
nValidF = 0
for i from 1 to nFrames
    selectObject: mfcc_obj
    t = Get time from frame number: i
    frame_time#[i] = t

    selectObject: formant_obj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    b1 = Get bandwidth at time: 1, t, "Hertz", "Linear"
    b2 = Get bandwidth at time: 2, t, "Hertz", "Linear"
    b3 = Get bandwidth at time: 3, t, "Hertz", "Linear"

    # Structural evidence is only meaningful here on a voiced/harmonic frame.
    # This prevents stable Burg poles on broadband noise from becoming phonetic features.
    selectObject: pitch_obj
    f0Probe = Get value at time: t, "Hertz", "Linear"
    if f0Probe = undefined
        f0Probe = 0
    endif
    selectObject: hnr_obj
    hnrProbe = Get value at time: t, "cubic"
    if hnrProbe = undefined
        hnrProbe = -100
    endif

    validF = 0
    if f1 <> undefined and f2 <> undefined and f3 <> undefined and b1 <> undefined and b2 <> undefined and b3 <> undefined
        if f0Probe > 0 and hnrProbe > 0 and f1 >= 150 and f1 <= min(1400, nyquist - 700) and f2 > f1 + 180 and f3 > f2 + 220 and f3 < nyquist - 60 and f3 - f1 >= 500 and b1 >= 20 and b1 <= min(600, 0.75 * f1) and b2 >= 20 and b2 <= min(900, 0.75 * f2) and b3 >= 20 and b3 <= min(1200, 0.75 * f3)
            validF = 1
        endif
    endif

    feat_formant_valid#[i] = validF
    if validF
        sumF1 += f1
        sumF2 += f2
        nValidF += 1
    endif
endfor

validFraction = nValidF / nFrames
formantFeaturesActive = (validFraction >= min_formant_valid_fraction)
if nValidF > 0
    fillF1 = sumF1 / nValidF
    fillF2 = sumF2 / nValidF
else
    fillF1 = 0
    fillF2 = 0
endif
if not formantFeaturesActive
    fillF1 = 0
    fillF2 = 0
endif

appendInfoLine: "  Structurally valid formants: ", nValidF, "/", nFrames, " (", fixed$(100 * validFraction, 1), "%)"
if formantFeaturesActive
    appendInfoLine: "  Formant features: ACTIVE (invalid frames use file-local neutral fill + validity flag)"
else
    appendInfoLine: "  Formant features: DISABLED (insufficient reliable evidence)"
endif
appendInfoLine: "  Silence threshold: ", fixed$(silence_threshold, 1), " dB (relative)"

# Pass 2: aligned feature extraction and rule labels.
for i from 1 to nFrames
    t = frame_time#[i]

    selectObject: mfcc_obj
    for c from 1 to 3
        v = Get value in frame: i, c
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

    if formantFeaturesActive and feat_formant_valid#[i]
        selectObject: formant_obj
        f1 = Get value at time: 1, t, "Hertz", "Linear"
        f2 = Get value at time: 2, t, "Hertz", "Linear"
    else
        f1 = fillF1
        f2 = fillF2
    endif
    feat_f1#[i] = f1
    feat_f2#[i] = f2

    selectObject: intensity_obj
    iv = Get value at time: t, "cubic"
    if iv = undefined
        iv = silence_threshold - 20
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
        f0 = 0
    endif
    feat_pitch#[i] = f0

    # Vowel requires reliable, structurally plausible formants.
    if iv < silence_threshold
        cat_silence#[i] = 1
    elsif formantFeaturesActive and feat_formant_valid#[i] and hnr > vowel_hnr_threshold and f0 > 0 and f1 > 300
        cat_vowel#[i] = 1
    elsif iv >= silence_threshold and hnr < fricative_hnr_max
        cat_consonant#[i] = 1
    else
        cat_other#[i] = 1
    endif
endfor

removeObject: pitch_obj, intensity_obj, formant_obj, mfcc_obj, hnr_obj
appendInfoLine: "  ", nFrames, " aligned MFCC frames analyzed"

# Class statistics.
nVowelFr = 0
nConsFr = 0
nOtherFr = 0
nSilFr = 0
for i from 1 to nFrames
    nVowelFr += cat_vowel#[i]
    nConsFr += cat_consonant#[i]
    nOtherFr += cat_other#[i]
    nSilFr += cat_silence#[i]
endfor
appendInfoLine: "  Classes: vowel ", fixed$(100 * nVowelFr / nFrames, 1), "% | consonant ", fixed$(100 * nConsFr / nFrames, 1), "% | other ", fixed$(100 * nOtherFr / nFrames, 1), "% | silence ", fixed$(100 * nSilFr / nFrames, 1), "%"

# ============================================
# NORMALIZE FEATURES
# ============================================
appendInfoLine: "Normalizing features..."

# Normalize the first seven continuous features to [0,1].
for whichFeature from 1 to 7
    if whichFeature = 1
        min_v = feat_mfcc_1#[1]
        max_v = feat_mfcc_1#[1]
    elsif whichFeature = 2
        min_v = feat_mfcc_2#[1]
        max_v = feat_mfcc_2#[1]
    elsif whichFeature = 3
        min_v = feat_mfcc_3#[1]
        max_v = feat_mfcc_3#[1]
    elsif whichFeature = 4
        min_v = feat_f1#[1]
        max_v = feat_f1#[1]
    elsif whichFeature = 5
        min_v = feat_f2#[1]
        max_v = feat_f2#[1]
    elsif whichFeature = 6
        min_v = feat_intensity#[1]
        max_v = feat_intensity#[1]
    else
        min_v = feat_hnr#[1]
        max_v = feat_hnr#[1]
    endif

    for i from 2 to nFrames
        if whichFeature = 1
            val = feat_mfcc_1#[i]
        elsif whichFeature = 2
            val = feat_mfcc_2#[i]
        elsif whichFeature = 3
            val = feat_mfcc_3#[i]
        elsif whichFeature = 4
            val = feat_f1#[i]
        elsif whichFeature = 5
            val = feat_f2#[i]
        elsif whichFeature = 6
            val = feat_intensity#[i]
        else
            val = feat_hnr#[i]
        endif
        if val < min_v
            min_v = val
        endif
        if val > max_v
            max_v = val
        endif
    endfor

    range_v = max_v - min_v
    if range_v < 0.0001
        range_v = 1
    endif

    for i from 1 to nFrames
        if whichFeature = 1
            feat_mfcc_1#[i] = (feat_mfcc_1#[i] - min_v) / range_v
        elsif whichFeature = 2
            feat_mfcc_2#[i] = (feat_mfcc_2#[i] - min_v) / range_v
        elsif whichFeature = 3
            feat_mfcc_3#[i] = (feat_mfcc_3#[i] - min_v) / range_v
        elsif whichFeature = 4
            feat_f1#[i] = (feat_f1#[i] - min_v) / range_v
        elsif whichFeature = 5
            feat_f2#[i] = (feat_f2#[i] - min_v) / range_v
        elsif whichFeature = 6
            feat_intensity#[i] = (feat_intensity#[i] - min_v) / range_v
        else
            feat_hnr#[i] = (feat_hnr#[i] - min_v) / range_v
        endif
    endfor
endfor

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
        feat_pitch#[i] = min(1, feat_pitch#[i] / max_pitch)
    else
        feat_pitch#[i] = 0
    endif
    feat_mfcc_1#[i] = max(0, min(1, feat_mfcc_1#[i]))
    feat_mfcc_2#[i] = max(0, min(1, feat_mfcc_2#[i]))
    feat_mfcc_3#[i] = max(0, min(1, feat_mfcc_3#[i]))
    feat_f1#[i] = max(0, min(1, feat_f1#[i]))
    feat_f2#[i] = max(0, min(1, feat_f2#[i]))
    feat_intensity#[i] = max(0, min(1, feat_intensity#[i]))
    feat_hnr#[i] = max(0, min(1, feat_hnr#[i]))
endfor

# ============================================
# BUILD PATTERN AND TRAIN FFNET
# ============================================
appendInfoLine: "Training neural network..."

# Ninth feature is explicit formant validity; imputed F1/F2 are never ambiguous.
n_features = 9
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
    Set value: i, 9, feat_formant_valid#[i] * formantFeaturesActive
endfor

selectObject: feat_table
To Matrix
feat_matrix = selected("Matrix")
To Pattern: 1
pattern = selected("PatternList")
selectObject: pattern
Formula: "max(0, min(1, self))"

Create Categories: "Targets"
categories = selected("Categories")
for i from 1 to nFrames
    selectObject: categories
    if cat_vowel#[i]
        Append category: "vowel"
    elsif cat_consonant#[i]
        Append category: "consonant"
    elsif cat_silence#[i]
        Append category: "silence"
    else
        Append category: "other"
    endif
endfor

# Praat orders the PRESENT categories alphabetically.
colIdx = 0
col_consonant = 0
if nConsFr > 0
    colIdx += 1
    col_consonant = colIdx
endif
col_other = 0
if nOtherFr > 0
    colIdx += 1
    col_other = colIdx
endif
col_silence = 0
if nSilFr > 0
    colIdx += 1
    col_silence = colIdx
endif
col_vowel = 0
if nVowelFr > 0
    colIdx += 1
    col_vowel = colIdx
endif
nClassesPresent = colIdx

weight_vowel# = zero#(nFrames)
weight_consonant# = zero#(nFrames)
weight_other# = zero#(nFrames)
weight_silence# = zero#(nFrames)

if nClassesPresent < 2
    appendInfoLine: "  One class only; FFNet skipped and rule labels used directly"
    for i from 1 to nFrames
        weight_vowel#[i] = cat_vowel#[i]
        weight_consonant#[i] = cat_consonant#[i]
        weight_other#[i] = cat_other#[i]
        weight_silence#[i] = cat_silence#[i]
    endfor
    removeObject: feat_table, feat_matrix, pattern, categories
else
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
        if abs(prev_cost - current_cost) < max(1e-12, prev_cost * 0.001)
            stale += 1
        else
            stale = 0
        endif
        prev_cost = current_cost
        iter += chunk
        if stale >= 5
            iter = training_iterations + 1
        endif
    endwhile
    appendInfoLine: "  Training complete"

    selectObject: ffnet
    plusObject: pattern
    # Layer 2 is the OUTPUT layer for a one-hidden-layer FFNet.
    To ActivationList: 2
    activations = selected("ActivationList")
    To Matrix
    activation_matrix = selected("Matrix")

    for i from 1 to nFrames
        selectObject: activation_matrix
        aV = -1e9
        aC = -1e9
        aO = -1e9
        aS = -1e9
        if col_vowel > 0
            aV = Get value in cell: i, col_vowel
        endif
        if col_consonant > 0
            aC = Get value in cell: i, col_consonant
        endif
        if col_other > 0
            aO = Get value in cell: i, col_other
        endif
        if col_silence > 0
            aS = Get value in cell: i, col_silence
        endif
        if aV = undefined
            aV = -1e9
        endif
        if aC = undefined
            aC = -1e9
        endif
        if aO = undefined
            aO = -1e9
        endif
        if aS = undefined
            aS = -1e9
        endif

        t_div = max(0.001, temperature)
        max_a = max(aV, max(aC, max(aO, aS)))
        eV = exp((aV - max_a) / t_div)
        eC = exp((aC - max_a) / t_div)
        eO = exp((aO - max_a) / t_div)
        eS = exp((aS - max_a) / t_div)
        sum_e = eV + eC + eO + eS
        if sum_e < 0.001
            sum_e = 1
        endif
        weight_vowel#[i] = eV / sum_e
        weight_consonant#[i] = eC / sum_e
        weight_other#[i] = eO / sum_e
        weight_silence#[i] = eS / sum_e
    endfor
    removeObject: feat_table, feat_matrix, pattern, categories, ffnet, activations, activation_matrix
endif

# ============================================
# CALCULATE + SMOOTH STRETCH FACTORS
# ============================================
appendInfoLine: "Calculating stretch factors..."
stretch_factor# = zero#(nFrames)
for i from 1 to nFrames
    factor = weight_vowel#[i] * vowel_stretch + weight_consonant#[i] * consonant_stretch + weight_other#[i] * other_stretch + weight_silence#[i] * silence_stretch
    stretch_factor#[i] = max(0.1, min(10, factor))
endfor

smooth_frames = round(smoothing_ms / (frame_step_sec * 1000))
if smooth_frames < 1
    smooth_frames = 1
endif
stretch_smooth# = zero#(nFrames)
for i from 1 to nFrames
    i1 = max(1, i - smooth_frames)
    i2 = min(nFrames, i + smooth_frames)
    sum_s = 0
    for k from i1 to i2
        sum_s += stretch_factor#[k]
    endfor
    stretch_smooth#[i] = sum_s / (i2 - i1 + 1)
endfor

# ============================================
# BUILD DURATION TIER + RESYNTHESIS
# ============================================
appendInfoLine: "Building duration tier..."
durationTier = Create DurationTier: "stretch", tmin, tmax
selectObject: durationTier
Add point: tmin, stretch_smooth#[1]
point_interval = 0.02
last_t = tmin - point_interval
for i from 1 to nFrames
    t = frame_time#[i]
    if t - last_t >= point_interval and t > tmin and t < tmax
        selectObject: durationTier
        Add point: t, stretch_smooth#[i]
        last_t = t
    endif
endfor
selectObject: durationTier
Add point: tmax, stretch_smooth#[nFrames]

appendInfoLine: "Resynthesizing..."
selectObject: workSnd
manip = To Manipulation: 0.01, 75, 600
selectObject: manip
plusObject: durationTier
Replace duration tier
selectObject: manip
finalOut = Get resynthesis (overlap-add)
Rename: sound_name$ + "_speedmap_" + presetName$

# Safety ceiling only; never boost a quiet output.
selectObject: finalOut
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 0.99
    Scale peak: 0.99
    appendInfoLine: "  Output safety ceiling applied"
else
    appendInfoLine: "  Natural output level retained"
endif

removeObject: workSnd, manip, durationTier

# ============================================
# VISUALIZATION
# ============================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    selectObject: finalOut
    out_dur = Get total duration

    Erase all
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Neural Phonetic Speed Mapper: " + sound_name$ + " [" + presetName$ + "]"

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

    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: finalOut
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text top: "no", fixed$(out_dur, 2) + " s (" + fixed$(out_dur/duration, 2) + "x)"

    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.9, 3.9
    Axes: tmin, tmax, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", tmin, tmax, 0, 1

    Colour: "{0.8, 0.3, 0.3}"
    for i from 2 to nFrames
        Draw line: frame_time#[i-1], weight_vowel#[i-1], frame_time#[i], weight_vowel#[i]
    endfor
    Colour: "{0.3, 0.4, 0.8}"
    for i from 2 to nFrames
        Draw line: frame_time#[i-1], weight_consonant#[i-1], frame_time#[i], weight_consonant#[i]
    endfor
    Colour: "{0.4, 0.7, 0.4}"
    for i from 2 to nFrames
        Draw line: frame_time#[i-1], weight_other#[i-1], frame_time#[i], weight_other#[i]
    endfor
    Colour: "{0.6, 0.6, 0.6}"
    for i from 2 to nFrames
        Draw line: frame_time#[i-1], weight_silence#[i-1], frame_time#[i], weight_silence#[i]
    endfor
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Weight"

    Select outer viewport: 0, 8, 4.2, 5.4
    Select inner viewport: 0.6, 7.6, 4.4, 5.3
    maxStretch = stretch_smooth#[1]
    minStretch = stretch_smooth#[1]
    for i from 2 to nFrames
        maxStretch = max(maxStretch, stretch_smooth#[i])
        minStretch = min(minStretch, stretch_smooth#[i])
    endfor
    yLo = min(0.9, minStretch * 0.9)
    yHi = max(1.1, maxStretch * 1.1)
    Axes: tmin, tmax, yLo, yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", tmin, tmax, yLo, yHi
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: tmin, 1, tmax, 1
    Solid line
    Colour: "{0.6, 0.3, 0.6}"
    Line width: 2
    for i from 2 to nFrames
        Draw line: frame_time#[i-1], stretch_smooth#[i-1], frame_time#[i], stretch_smooth#[i]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Stretch"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 5.5, 6.0
    Font size: 8
    Colour: "Black"
    validityLabel$ = "formant evidence " + fixed$(100 * validFraction, 1) + "%"
    if not formantFeaturesActive
        validityLabel$ = validityLabel$ + " (disabled)"
    endif
    Text: 0.5, "centre", 0.5, "half", validityLabel$
endif

# ============================================
# OUTPUT
# ============================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: finalOut
out_dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Original: ", fixed$(duration, 2), " s"
appendInfoLine: "New: ", fixed$(out_dur, 2), " s"
appendInfoLine: "Ratio: ", fixed$(out_dur / duration, 2), "x"
appendInfoLine: "Formant evidence: ", fixed$(100 * validFraction, 1), "%"

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut
