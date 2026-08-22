# ============================================================
# Praat AudioTools - Neural_Adaptive_Phonetic_Vibrato.praat
# Author: Shai Cohen 
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5 (2026) - Suite-standard visualization
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
#   - Temperature-shaped weights visualization
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

# ============================================================
# Changelog v1.4 (2026):
#
#   THE EFFECT WAS TOO SUBTLE, and the cause was structural rather
#   than a bug. The wet weight is bounded by p(vowel), and p(vowel) is
#   bounded by how peaked a softmax over FOUR near-equal activations
#   can be. Measured on the test signal: the most vowel-like frame in
#   the entire file reached only w = 0.2199, so even at the effect's
#   strongest point the dry path sat at 0.78 and the vibrato was
#   nearly inaudible. Every preset behaved this way.
#
#   The absolute scale of that mask carries no useful information -
#   it is an artefact of having four categories and of how imbalanced
#   they are in a given file. Only the SHAPE is meaningful. So the
#   mask is now normalised by its own peak and scaled to a new
#   Effect_strength control: the most vowel-like frame gets exactly
#   Effect_strength of wet, every other frame keeps its relative
#   weight, and consonants stay dry because the confidence gate has
#   already zeroed them before the rescale.
#
#   Effect_strength defaults to 0.85, and each preset sets its own
#   (Subtle Thickener 0.45 up to Dreamy Wash 1.00), so the presets
#   stay distinct instead of all collapsing to "barely there".
#
#   A file whose mask never rises above 0.02 anywhere has no
#   vowel-like frame at all; rescaling that up to full wet would be
#   wrong, so it bypasses to dry and says so.
#
# ============================================================
# Changelog v1.3 (2026):
#
#   CRITICAL - categories the network does not have were still taking
#     softmax weight. v1.2 set a missing category's activation to 0 and
#     then exponentiated it anyway; exp(0 - max) is a positive number,
#     not zero. Measured with only vowel (0.8) and other (0.2) present
#     at T = 0.45:
#       v1.2:    vowel 0.6244, other 0.1646,
#                fricative(absent) 0.1055, silence(absent) 0.1055
#                -> 21.11% of the probability mass went to outputs
#                   that do not exist
#       correct: vowel 0.7914, other 0.2086
#     The degenerate case is worse: on an all-vowel file pVowel capped
#     at 0.7112 instead of 1.0000, so the wet mask could never open
#     fully. Absent categories are now excluded from the denominator.
#
#   2 - Formant validity is now actually implemented. v1.2's changelog
#     claimed it; the code still filled undefined formants with
#     500 / 1500 / 2500 Hz, which ARE canonical vowel formants - so a
#     frame whose formant analysis failed looked like a textbook vowel
#     to the labelling rule (which only asks F1 > 300) and to the
#     network. There is now a formantValid# flag, the vowel rule
#     requires it, and missing values are filled with the file's own
#     valid mean instead of a vowel-shaped constant.
#
#   3 - Two documentation corrections, both mine: the header still said
#     Version 1.1, and the note under the form described
#     Confidence_threshold as a margin test when the implementation
#     gates on p(vowel). See also the correction inside item 8 below.
#
#   4 - The no-vowel message no longer tells the user to lower a
#     "Vowel HNR threshold" that is not in the form. It now says what
#     actually happened and what kind of input would work.
#
# ============================================================
# Changelog v1.2 (2026):
#
#   CRITICAL 1 - the vibrato was keyed to the WRONG category.
#     The script read activation columns 1..4 as vowel, fricative,
#     silence, other, and drove the wet mask from column 1. Praat sorts
#     an FFNet's outputs by category name. Verified on 6.4.42 with
#     categories inserted in the order vowel, fricative, silence,
#     other:
#       output 1 -> 'fricative'
#       output 2 -> 'other'
#       output 3 -> 'silence'
#       output 4 -> 'vowel'
#     So w_vowel was the FRICATIVE weight and the effect ran almost
#     exactly inverted from its stated design: vibrato on the
#     consonants, dry on the vowels. Every category plot was mislabelled
#     with it. v1.2 asks the network for each output's category by name
#     (Get category of output unit) and builds an index map.
#
#   CRITICAL 2 - a missing category shifted or broke everything.
#     The number of outputs is the number of DISTINCT categories
#     present. Verified: with no 'vowel' frame the net has 3 outputs,
#     labelled fricative / other / silence - so the old
#     "Get value in cell: i, 4" read a column that does not exist, and
#     the no-vowel guard could not fire because the script died first.
#     v1.2 maps by name, treats a missing category's weight as 0, and
#     turns "no vowel found" into a real dry bypass.
#
#   CRITICAL 3 - Sound & IntensityTier: Multiply renormalised each path
#     to a peak of 0.9, destroying the mix ratio. Verified: a 0.5-peak
#     tone multiplied by a -40 dB tier gives peak 0.00499971 with
#     Multiply: "no" (correct: 0.5 * 10^-2) and 0.90000 with
#     Multiply: "yes". Each of the three paths was normalised
#     INDEPENDENTLY, so a vowel weight of 0.01 and a dry weight of 0.99
#     both arrived at 0.9 and summed at roughly equal loudness. The
#     mask therefore controlled almost nothing. v1.2 uses
#     Multiply: "no" on all three paths and applies one conditional
#     limiter after the sum.
#
#   4 - Confidence_threshold now does something. It appeared in the
#     form and in every preset and was never read anywhere in the
#     script, so all five presets behaved identically in that respect.
#     It gates on p(vowel) with a soft knee: 0 below the threshold,
#     ramping to full at twice it, so the mask does not step.
#     NOTE: implemented first as a MARGIN test (p(vowel) minus its
#     nearest rival), which is stricter and more principled and which
#     turned out to be unusable. On ordinary material the classes are
#     badly imbalanced - 16 vowel frames against 95 fricative and 181
#     other on the test signal - and the vowel probability never leads
#     at all (best margin -0.00606), so every preset rendered pure dry.
#     The margin form is left in the code as a commented alternative
#     for balanced material.
#
#   5 - Voiced state is separated from F0. Unvoiced frames were given
#     z = 0.5 for pitch and then min-max normalised with real pitches,
#     which puts them near the TOP of a 100-300 Hz file's range - so
#     the "voicedness" boost could favour fricatives and silence. There
#     is now an explicit voiced flag, pitch is read only where voiced,
#     and undefined formants are flagged rather than filled with
#     500/1500/2500 Hz, which reads as a canonical vowel.
#
#   6 - Frame times come from the MFCC object (Get time from frame
#     number) instead of frame_step * (i - 0.5). The first MFCC frame
#     centre is not necessarily half a step in, so MFCC rows were being
#     paired with pitch, formant and intensity values from a slightly
#     different instant.
#
#   7 - The silence threshold is now relative (max intensity - 35 dB).
#     A fixed 45 dB SPL cut meant the same speech, attenuated by 20 dB,
#     relabelled as silence and produced a different mask.
#
#   8 - Boundary artefacts are SUPPRESSED, not prevented. Praat returns
#     0 outside a Sound's domain, so within one vibrato depth of each
#     edge one channel reads past the boundary and drops out - up to
#     5 ms on Wide & Slow, and asymmetric between channels. A final
#     edge fade, longer than the vibrato depth, covers the region.
#     CORRECTION (v1.3): v1.2's changelog said the work sound was
#     "padded before modulation and trimmed after". It was not - no
#     padding, extension, reflection or post-trim was ever written.
#     The fade is a real improvement and covers the affected span, but
#     the out-of-domain reads still happen and this entry now says so.
#
#   9 - Random_seed added (0 = unpredictable). FFNet initialisation and
#     training are stochastic, so two runs could produce different
#     masks; the generator is returned to its safe state afterwards.
#
#   10 - Stereo_width is validated to [0, 1]. It was an unbounded real,
#     where negatives invert phase.
#
#   11 - Ch_Left and Ch_Right are always removed. They were only
#     cleaned up inside the visualization branch, so running with the
#     drawing off left two Sounds behind.
#
#   12 - Naming and framing:
#     - Form, Info banner and header all said different versions.
#     - "Temperature-shaped weights" -> temperature-shaped activation weights.
#       An ActivationList already holds 0..1 values, not logits, so the
#       result is a shaped weighting, not a calibrated probability.
#     - The FFNet is trained on rules this script derives from THIS
#       file, tested on the same frames, and used only on that file.
#       There is no corpus, no held-out set and no ground truth. It is
#       per-file rule distillation into a smooth vowel-likelihood mask
#       - useful, but not learned phonetics.
#     - Output is synthetic stereo built from a mono fold-down; source
#       stereo is not preserved.
#
# ============================================================

# Changelog v1.5 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; feature extraction, heuristic
#     frame labels, per-file FFNet distillation, category mapping,
#     adaptive vowel mask, stereo vibrato and final limiting are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, suite-standard title/subtitle, typography, neutral
#     panel backgrounds, summary strip and full-page export viewport.
#   - Preserved all six visual ideas: source, stereo result, predicted
#     category timeline, adaptive wet/dry mask, F1/F2 feature space and
#     temperature-shaped category weights.
#   - Corrected visual terminology: ActivationList-derived category
#     weights are not presented as calibrated softmax probabilities.
#
form Neural Phonetic Vibrato v1.5
    optionmenu Preset 1
        option Manual
        option Lush Chorus
        option Wide & Slow
        option Nervous Shimmer
        option Subtle Thickener
        option Dreamy Wash
    positive Vibrato_rate_hz 6.0
    positive Vibrato_depth_ms 2.5
    positive Confidence_threshold 0.15
    positive Temperature 0.45
    positive Voiced_boost 0.4
    positive Effect_strength 0.85
    real Stereo_width 0.9
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Confidence_threshold gates on p(vowel) itself: below it the wet path
# is silent, and it ramps to full at twice the threshold, so the mask
# does not step. (A stricter margin form - p(vowel) minus its nearest
# rival - is in the code as a commented alternative; it zeroes the wet
# path on class-imbalanced material.) Output is synthetic stereo derived
# from a mono fold-down. Random_seed 0 = unpredictable.

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
    effect_strength = 0.90
    presetName$ = "LushChorus"
elsif preset = 3
    # Wide & Slow
    vibrato_rate_hz = 2.5
    vibrato_depth_ms = 5.0
    confidence_threshold = 0.10
    temperature = 0.5
    stereo_width = 1.0
    effect_strength = 0.85
    presetName$ = "WideSlow"
elsif preset = 4
    # Nervous Shimmer
    vibrato_rate_hz = 8.5
    vibrato_depth_ms = 1.5
    confidence_threshold = 0.15
    temperature = 0.4
    stereo_width = 0.7
    effect_strength = 0.95
    presetName$ = "NervousShimmer"
elsif preset = 5
    # Subtle Thickener
    vibrato_rate_hz = 5.0
    vibrato_depth_ms = 1.2
    confidence_threshold = 0.25
    temperature = 0.6
    stereo_width = 0.5
    effect_strength = 0.45
    presetName$ = "SubtleThickener"
elsif preset = 6
    # Dreamy Wash
    vibrato_rate_hz = 4.0
    vibrato_depth_ms = 4.0
    confidence_threshold = 0.05
    temperature = 0.8
    stereo_width = 1.0
    effect_strength = 1.00
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
writeInfoLine: "=== Neural Phonetic Vibrato v1.5 ==="
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

# v1.2 fix 7: relative, not absolute. A fixed 45 dB SPL cut meant the
# same speech attenuated by 20 dB relabelled as silence.
selectObject: intensity
maxIntensityDb = Get maximum: 0, 0, "Parabolic"
if maxIntensityDb = undefined
    maxIntensityDb = 60
endif
silence_intensity_threshold = maxIntensityDb - 35
if silence_intensity_threshold < 5
    silence_intensity_threshold = 5
endif
appendInfoLine: "  Silence threshold: ", fixed$(silence_intensity_threshold, 1),
    ... " dB (max ", fixed$(maxIntensityDb, 1), " - 35)"

# v1.2 fix 6: take frame centres from the MFCC object itself. The
# first MFCC frame centre is x1, not half a step in, so
# frame_step * (i - 0.5) paired each MFCC row with pitch, formant and
# intensity values from a slightly different instant.
frameTime# = zero#(rows_target)
for i from 1 to rows_target
    selectObject: mfcc
    frameTime#[i] = Get time from frame number: i
endfor

# ============================================
# VALIDATION + SEED  (v1.2 fixes 9, 10)
# ============================================
if stereo_width < 0
    stereo_width = 0
    appendInfoLine: "  ! Stereo_width < 0 (phase inversion) -> 0"
endif
if stereo_width > 1
    stereo_width = 1
    appendInfoLine: "  ! Stereo_width > 1 -> 1"
endif

# FFNet initialisation and training are stochastic; without a seed two
# runs could produce different masks from the same input.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif
appendInfoLine: "  Seed: ", seedLabel$


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
# v1.3: track formant VALIDITY. v1.2's changelog claimed this and it
# was never written - the old 500 / 1500 / 2500 Hz fill stayed. Those
# are canonical vowel formants, so a frame whose formant analysis
# FAILED looked like a textbook vowel to both the labelling rule
# (which only asks F1 > 300) and the network. Missing values are now
# filled with the file's own valid mean, which carries no vowel bias,
# and the validity flag gates the vowel rule.
formantValid# = zero#(rows_target)
sumF1 = 0
sumF2 = 0
sumF3 = 0
nValidF = 0
for i from 1 to rows_target
    selectObject: formant
    t = frameTime#[i]
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    selectObject: formant
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    selectObject: formant
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    if f1 <> undefined and f2 <> undefined and f3 <> undefined
        formantValid#[i] = 1
        nValidF = nValidF + 1
        sumF1 = sumF1 + f1
        sumF2 = sumF2 + f2
        sumF3 = sumF3 + f3
    endif
endfor
if nValidF > 0
    fillF1 = sumF1 / nValidF
    fillF2 = sumF2 / nValidF
    fillF3 = sumF3 / nValidF
else
    # nothing valid anywhere: neutral values, and no frame can pass
    # the vowel rule because formantValid# is 0 throughout
    fillF1 = 500
    fillF2 = 1500
    fillF3 = 2500
endif
appendInfoLine: "  Formants valid in ", nValidF, "/", rows_target, " frames"

for i from 1 to rows_target
    if formantValid#[i] = 1
        selectObject: formant
        t = frameTime#[i]
        f1 = Get value at time: 1, t, "Hertz", "Linear"
        selectObject: formant
        f2 = Get value at time: 2, t, "Hertz", "Linear"
        selectObject: formant
        f3 = Get value at time: 3, t, "Hertz", "Linear"
    else
        f1 = fillF1
        f2 = fillF2
        f3 = fillF3
    endif
    selectObject: feature_matrix
    Set value: i, 4, f1 / 1000
    selectObject: feature_matrix
    Set value: i, 5, f2 / 1000
    selectObject: feature_matrix
    Set value: i, 6, f3 / 1000
endfor

# 3. Intensity
selectObject: intensity
for i from 1 to rows_target
    t = frameTime#[i]
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
    t = frameTime#[i]
    v = Get value at time: t, "cubic"
    if v = undefined
        v = 0
    endif
    selectObject: feature_matrix
    Set value: i, 8, v / 20
    selectObject: harmonicity
endfor

# 5. Pitch
# v1.2 fix 5: an explicit voiced flag, and pitch read only where the
# frame is voiced. v1.1 wrote z = 0.5 for unvoiced frames and then
# min-max normalised the column with real pitches, so unvoiced frames
# landed near the TOP of a 100-300 Hz file's range and the voicedness
# boost could favour exactly the frames it was meant to avoid.
voicedFlag# = zero#(rows_target)
sumVoicedZ = 0
nVoicedFrames = 0
for i from 1 to rows_target
    selectObject: pitch
    t = frameTime#[i]
    v = Get value at time: t, "Hertz", "Linear"
    if v = undefined or v <= 0
        voicedFlag#[i] = 0
    else
        voicedFlag#[i] = 1
        nVoicedFrames = nVoicedFrames + 1
        sumVoicedZ = sumVoicedZ + v / 500
    endif
endfor
if nVoicedFrames > 0
    meanVoicedZ = sumVoicedZ / nVoicedFrames
else
    meanVoicedZ = 0
endif
for i from 1 to rows_target
    if voicedFlag#[i] = 1
        selectObject: pitch
        t = frameTime#[i]
        v = Get value at time: t, "Hertz", "Linear"
        z = v / 500
    else
        # a neutral fill that is the voiced MEAN, so an unvoiced frame
        # cannot masquerade as a high pitch after normalisation
        z = meanVoicedZ
    endif
    selectObject: feature_matrix
    Set value: i, 9, z
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
    t = frameTime#[i]
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
    t = frameTime#[i]
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
    t = frameTime#[i]
    v = Get value at time: t, "Hertz", "Linear"
    if v = undefined or v <= 0
        v = 0
    endif
    selectObject: raw_data
    Set value: i, 3, v
    selectObject: pitch
endfor

selectObject: formant
for i from 1 to rows_target
    t = frameTime#[i]
    v = Get value at time: 1, t, "Hertz", "Linear"
    if v = undefined
        # v1.3: the file's own valid mean, not a canonical vowel F1
        v = fillF1
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
    t = frameTime#[i]
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
    elsif formantValid#[i] = 1 and hnr_val > vowel_hnr_threshold and f0_val > 0 and f1_val > 300
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

# No vowels detected: the network has no positive vowel examples to learn
# from, so the vibrato mask will stay near zero and the output will sound
# essentially like the dry input. Warn rather than fail.
if count_vowel = 0
    appendInfoLine: ""
    appendInfoLine: "  WARNING: no vowel frames detected. The vibrato effect"
    appendInfoLine: "  will be inaudible (no vowel regions to apply it to)."
    appendInfoLine: "  The wet path is bypassed; the output is the dry signal."
    appendInfoLine: "  This input has no frame that is voiced, harmonic and"
    appendInfoLine: "  above the silence floor with a valid F1 - try speech or"
    appendInfoLine: "  sung material rather than noise or percussion."
endif

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

# v1.2 CRITICAL 1 + 2: ask the network which output is which. Praat
# sorts FFNet outputs by category NAME, and creates one output per
# DISTINCT category actually present. Verified on 6.4.42 with
# categories inserted vowel, fricative, silence, other:
#   output 1 'fricative'  2 'other'  3 'silence'  4 'vowel'
# v1.1 read column 1 as the vowel weight, so the wet mask was driven
# by the FRICATIVE probability - the effect ran inverted. And with no
# vowel frame at all the net has only 3 outputs, so reading column 4
# was an access past the end.
selectObject: ffnet
nOutputs = Get number of outputs
idxVowel = 0
idxFricative = 0
idxSilence = 0
idxOther = 0
for k from 1 to nOutputs
    selectObject: ffnet
    catName$ = Get category of output unit: k
    if catName$ = "vowel"
        idxVowel = k
    elsif catName$ = "fricative"
        idxFricative = k
    elsif catName$ = "silence"
        idxSilence = k
    elsif catName$ = "other"
        idxOther = k
    endif
endfor
appendInfoLine: "  FFNet outputs: ", nOutputs,
    ... "   vowel=", idxVowel, " fricative=", idxFricative,
    ... " silence=", idxSilence, " other=", idxOther
if idxVowel = 0
    appendInfoLine: "  ! No 'vowel' category in this file - the wet path"
    appendInfoLine: "    is bypassed entirely and the output is the dry signal."
endif

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
rawMask# = zero#(rows_target)
viz_w_vowel# = zero#(rows_target)
viz_w_dry# = zero#(rows_target)
viz_time# = zero#(rows_target)
viz_predicted_category# = zero#(rows_target)
viz_softmax# = zero#(rows_target * 4)

for i from 1 to rows_target
    t = frameTime#[i]
    viz_time#[i] = t
    
    # v1.2 CRITICAL 1 + 2: read each category by its mapped output
    # index, and treat a category the network does not have as 0.
    selectObject: activation_matrix
    if idxVowel > 0
        aVowel = Get value in cell: i, idxVowel
    else
        aVowel = 0
    endif
    if idxFricative > 0
        selectObject: activation_matrix
        aFric = Get value in cell: i, idxFricative
    else
        aFric = 0
    endif
    if idxSilence > 0
        selectObject: activation_matrix
        aSil = Get value in cell: i, idxSilence
    else
        aSil = 0
    endif
    if idxOther > 0
        selectObject: activation_matrix
        aOther = Get value in cell: i, idxOther
    else
        aOther = 0
    endif

    # Temperature-shaped activation weights. An ActivationList already
    # holds 0..1 values, not logits, so this is a shaped weighting -
    # v1.1 called it "softmax confidence", which overstates it.
    tdiv = temperature
    if tdiv <= 0.0001
        tdiv = 0.0001
    endif
    # v1.3 CRITICAL: a category the network does NOT have must not
    # appear in the denominator. v1.2 set its activation to 0 and then
    # exponentiated it anyway, and exp(0 - max) is a positive number.
    # Measured with only vowel (0.8) and other (0.2) present, T=0.45:
    #   v1.2   vowel 0.6244  other 0.1646
    #          fricative(absent) 0.1055  silence(absent) 0.1055
    #          -> 21.11% of the weight went to categories with no output
    #   correct vowel 0.7914  other 0.2086
    # Worse in the degenerate case: an all-vowel file capped pVowel at
    # 0.7112 instead of 1.0000, so the wet mask could never open fully.
    max_a = max(aVowel, max(aFric, max(aSil, aOther)))
    if idxVowel > 0
        eVowel = exp((aVowel - max_a) / tdiv)
    else
        eVowel = 0
    endif
    if idxFricative > 0
        eFric = exp((aFric - max_a) / tdiv)
    else
        eFric = 0
    endif
    if idxSilence > 0
        eSil = exp((aSil - max_a) / tdiv)
    else
        eSil = 0
    endif
    if idxOther > 0
        eOther = exp((aOther - max_a) / tdiv)
    else
        eOther = 0
    endif
    denom = eVowel + eFric + eSil + eOther
    if denom <= 0
        denom = 1e-12
    endif

    pVowel = eVowel / denom
    pFric = eFric / denom
    pSil = eSil / denom
    pOther = eOther / denom

    # legacy names kept for the visualization panels
    p1 = pVowel
    p2 = pFric
    p3 = pSil
    p4 = pOther

    # Store for visualization
    viz_softmax#[(i-1)*4 + 1] = pVowel
    viz_softmax#[(i-1)*4 + 2] = pFric
    viz_softmax#[(i-1)*4 + 3] = pSil
    viz_softmax#[(i-1)*4 + 4] = pOther

    # Predicted category (argmax) - 1 vowel, 2 fricative, 3 silence,
    # 4 other, matching the visualization legend
    if pVowel >= pFric and pVowel >= pSil and pVowel >= pOther
        viz_predicted_category#[i] = 1
    elsif pFric >= pSil and pFric >= pOther
        viz_predicted_category#[i] = 2
    elsif pSil >= pOther
        viz_predicted_category#[i] = 3
    else
        viz_predicted_category#[i] = 4
    endif
    
    w_vowel = pVowel
    w_rest  = pFric + pSil + pOther

    # v1.2 fix 4: Confidence_threshold finally does something. It is a
    # MARGIN - how far the vowel weight leads its nearest rival - with
    # a soft knee, so the mask ramps instead of stepping. v1.1 declared
    # this parameter, set it in every preset, and never read it.
    # The gate is on p(vowel) itself, with a soft knee: 0 below the
    # threshold, ramping to full at twice it.
    #
    # I first implemented this as a MARGIN test - p(vowel) minus its
    # nearest rival - which is the stricter and more principled form.
    # It silenced the wet path completely on ordinary material: with
    # 16 vowel frames against 95 fricative and 181 other, the vowel
    # probability never led at all (best margin -0.00606), so every
    # preset produced pure dry. Class imbalance is the normal case for
    # this feature set, so the margin form is unusable as the only
    # gate. It is kept here as a commented alternative for anyone
    # working with balanced material:
    #   rival = max(pFric, max(pSil, pOther))
    #   margin = pVowel - rival
    if pVowel <= confidence_threshold
        confGate = 0
    elsif pVowel >= confidence_threshold * 2
        confGate = 1
    else
        confGate = (pVowel - confidence_threshold) / confidence_threshold
    endif
    w_vowel = w_vowel * confGate

    # v1.2 fix 5: the boost uses an explicit VOICED flag. v1.1 gave
    # unvoiced frames z = 0.5 for pitch and then min-max normalised
    # that alongside real pitches, which lands near the top of a
    # 100-300 Hz file's range - so the "voicedness" term could favour
    # fricatives and silence, the opposite of its purpose.
    selectObject: feature_matrix
    norm_hnr = Get value: i, 8
    selectObject: feature_matrix
    norm_f0 = Get value: i, 9
    if voicedFlag#[i] = 1
        voicedness = (norm_hnr * 0.5) + (norm_f0 * 0.5)
    else
        voicedness = 0
    endif
    adapt_weight = 1 + voiced_boost * (voicedness - 0.5) * 2
    if adapt_weight < 0
        adapt_weight = 0
    endif

    w_vowel = w_vowel * adapt_weight

    # v1.2 CRITICAL 2: with no vowel category at all, bypass to dry.
    if idxVowel = 0
        w_vowel = 0
    endif

    total = w_vowel + w_rest
    if total <= 0
        total = 1e-12
    endif
    w_vowel = w_vowel / total
    if w_vowel > 1
        w_vowel = 1
    endif
    # v1.4: store the RAW mask. The tiers are written in a second pass,
    # after the mask has been scaled to Effect_strength (see below).
    rawMask#[i] = w_vowel
    w_dry = 1.0 - w_vowel

    viz_w_vowel#[i] = w_vowel
    viz_w_dry#[i] = w_dry
    
endfor

# ============================================================
# MASK SCALING  (v1.4)
# ============================================================
# The raw wet weight is bounded by p(vowel), and p(vowel) is bounded by
# how peaked a softmax over FOUR near-equal activations can be. On real
# material that ceiling is low: measured on the test signal, the most
# vowel-like frame in the whole file reached only w = 0.2199, so the
# dry path sat at 0.78 even at the effect's strongest point and the
# vibrato was barely audible. That is a property of the descriptor, not
# a defect - but it means the ABSOLUTE scale of the mask carries no
# useful information, only its SHAPE does.
#
# So the mask is normalised by its own peak and then scaled to
# Effect_strength: the most vowel-like frame in the file gets exactly
# Effect_strength of wet, everything else keeps its relative weight,
# and consonants stay dry because the confidence gate already zeroed
# them BEFORE this rescale.
rawPeak = 0
for i from 1 to rows_target
    if rawMask#[i] > rawPeak
        rawPeak = rawMask#[i]
    endif
endfor

appendInfoLine: "  Raw mask peak: ", fixed$(rawPeak, 4),
    ... "  -> scaled to Effect_strength ", fixed$(effect_strength, 2)

# A mask that never rises anywhere means no vowel-like frame was found;
# rescaling noise up to full wet would be wrong, so bypass to dry.
maskFloor = 0.02
if rawPeak < maskFloor
    appendInfoLine: "  ! Mask never rises above ", fixed$(maskFloor, 2),
        ... " - no vowel-like frame found; wet path bypassed."
    maskScale = 0
else
    maskScale = effect_strength / rawPeak
endif

for i from 1 to rows_target
    t = frameTime#[i]
    w_vowel = rawMask#[i] * maskScale
    if w_vowel > 1
        w_vowel = 1
    endif
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

# v1.2 CRITICAL 3: Multiply: "no". The bare "Multiply" renormalises the
# result to a peak of 0.9 - verified on 6.4.42: a 0.5-peak tone times a
# -40 dB tier gives 0.00499971 with "no" (correct) and 0.90000 with
# "yes". v1.1 normalised all THREE paths independently, so a vowel
# weight of 0.01 and a dry weight of 0.99 both arrived at 0.9 and were
# summed at roughly equal loudness. The mask barely controlled the mix
# at all, which is why Temperature and Voiced_boost seemed inert.
# One conditional limiter is applied after the sum instead.
selectObject: s_vib_L
plusObject: mask_vib
Multiply: "no"
s_vib_L_masked = selected("Sound")
Rename: "Mix_Vib_L"

selectObject: s_vib_R
plusObject: mask_vib
Multiply: "no"
s_vib_R_masked = selected("Sound")
Rename: "Mix_Vib_R"

selectObject: s_dry
plusObject: mask_dry
Multiply: "no"
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

# v1.2 CRITICAL 3: a CONDITIONAL limiter, not an unconditional
# renormalisation. With the per-path normalisation removed, the mix
# ratio the mask computed is what reaches the output; only rescale if
# the sum actually clips.
selectObject: final_stereo
finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.99
    selectObject: final_stereo
    Scale peak: 0.99
    appendInfoLine: "  Limiter engaged (sum peaked at ", fixed$(finalPeak, 3), ")"
endif

# v1.2 fix 8: a short fade at each end. Praat reads 0 outside a Sound's
# domain, so within one vibrato depth of each edge one channel read
# past the boundary while the other did not - a dropout, asymmetric
# between channels, up to 5 ms on Wide & Slow.
selectObject: final_stereo
fsDur = Get total duration
edgeF = vibrato_depth_ms / 1000 + 0.002
if edgeF > fsDur * 0.1
    edgeF = fsDur * 0.1
endif
if edgeF > 0.0002
    efS$ = fixed$(edgeF, 8)
    selectObject: final_stereo
    Formula: "if x - xmin < " + efS$ + " then self * ((x - xmin) / " + efS$ + ") else self fi"
    selectObject: final_stereo
    Formula: "if xmax - x < " + efS$ + " then self * ((xmax - x) / " + efS$ + ") else self fi"
endif

# v1.2 fix 9: all stochastic work is done.
random_initializeSafelyAndUnpredictably ()

# Store for visualization
viz_left = ch_L
viz_right = ch_R

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    appendInfoLine: "Step 6: Drawing visualization..."

    selectObject: final_stereo
    vizOutDur = Get total duration
    vizOutPeak = Get absolute extremum: 0, 0, "None"
    vizOutChannels = Get number of channels

    vizSoundName$ = replace$(sound_name$, "_", "\_ ", 0)

    if idxVowel > 0
        vowelOutputState$ = "vowel output present"
    else
        vowelOutputState$ = "no vowel output - dry bypass"
    endif

    pageHeight = 8.55
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight

    # Category palette shared across timeline, feature space and weights.
    cat_colors$# = {"", "", "", ""}
    # Vowel
    cat_colors$#[1] = "{0.25, 0.65, 0.35}"
    # Fricative
    cat_colors$#[2] = "{0.85, 0.50, 0.20}"
    # Silence
    cat_colors$#[3] = "{0.60, 0.60, 0.60}"
    # Other
    cat_colors$#[4] = "{0.35, 0.45, 0.75}"

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Neural Phonetic Vibrato v1.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizSoundName$ + " | " + presetName$ + " | FFNet 18-24-" + string$(nOutputs) + " | per-file rule distillation"

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.66, 1.42
    Select inner viewport: 0.60, 7.70, 0.78, 1.26
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Source Sound | " + fixed$(duration, 2) + " s"

    # === Stereo result waveforms ===
    Select outer viewport: 0, 4, 1.58, 2.42
    Select inner viewport: 0.60, 3.85, 1.72, 2.24
    selectObject: viz_left
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result L"
    Text top: "no", "Left vibrato path"

    Select outer viewport: 4, 8, 1.58, 2.42
    Select inner viewport: 4.45, 7.70, 1.72, 2.24
    selectObject: viz_right
    Colour: "{0.75, 0.45, 0.25}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result R"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Right vibrato path"

    # === FFNet predicted-category timeline ===
    max_time = duration
    Select outer viewport: 0, 8, 2.62, 3.88
    Select inner viewport: 0.80, 7.70, 2.84, 3.66
    Axes: 0, max_time, 0.5, 4.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time, 0.5, 4.5

    for i from 1 to rows_target
        t = viz_time#[i]
        cat = viz_predicted_category#[i]
        y_pos = cat
        Paint rectangle: cat_colors$#[cat], t - frame_step_seconds/2, t + frame_step_seconds/2, y_pos - 0.34, y_pos + 0.34
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Category"
    Text bottom: "no", "Time (s)"
    Text top: "no", "FFNet Predicted Categories | 1 vowel | 2 fricative | 3 silence | 4 other"

    # === Adaptive wet/dry mask ===
    Select outer viewport: 0, 8, 4.08, 5.36
    Select inner viewport: 0.60, 7.70, 4.30, 5.14
    Axes: 0, max_time, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time, 0, 1.1

    Colour: "{0.80, 0.80, 0.80}"
    Dashed line
    Draw line: 0, effect_strength, max_time, effect_strength
    Solid line

    Colour: "{0.75, 0.25, 0.25}"
    Line width: 2
    for i from 1 to rows_target - 1
        Draw line: viz_time#[i], viz_w_vowel#[i], viz_time#[i+1], viz_w_vowel#[i+1]
    endfor

    Colour: "{0.25, 0.45, 0.75}"
    for i from 1 to rows_target - 1
        Draw line: viz_time#[i], viz_w_dry#[i], viz_time#[i+1], viz_w_dry#[i+1]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Weight"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Adaptive Mixing Mask | red vibrato | blue dry | dashed effect-strength ceiling"

    # === Feature space and category weights: 4/4 grid ===
    # Feature-space ranges from values actually plotted.
    min_f1 = 1e9
    max_f1 = -1e9
    min_f2 = 1e9
    max_f2 = -1e9
    for i from 1 to rows_target
        f1 = viz_f1#[i]
        f2 = viz_f2#[i]
        if f1 > 0 and f2 > 0
            if f1 < min_f1
                min_f1 = f1
            endif
            if f1 > max_f1
                max_f1 = f1
            endif
            if f2 < min_f2
                min_f2 = f2
            endif
            if f2 > max_f2
                max_f2 = f2
            endif
        endif
    endfor

    if max_f1 <= min_f1
        min_f1 = 200
        max_f1 = 1200
    else
        f1pad = (max_f1 - min_f1) * 0.08
        min_f1 = max(0, min_f1 - f1pad)
        max_f1 = max_f1 + f1pad
    endif
    if max_f2 <= min_f2
        min_f2 = 500
        max_f2 = 3000
    else
        f2pad = (max_f2 - min_f2) * 0.08
        min_f2 = max(0, min_f2 - f2pad)
        max_f2 = max_f2 + f2pad
    endif

    Select outer viewport: 0, 4, 5.58, 7.18
    Select inner viewport: 0.60, 3.85, 5.84, 6.94
    Axes: min_f1, max_f1, min_f2, max_f2
    Paint rectangle: "{0.97, 0.97, 0.97}", min_f1, max_f1, min_f2, max_f2

    step = max(1, floor(rows_target / 400))
    for i from 1 to rows_target
        if i mod step = 0
            cat = viz_predicted_category#[i]
            f1 = viz_f1#[i]
            f2 = viz_f2#[i]
            if f1 >= min_f1 and f1 <= max_f1 and f2 >= min_f2 and f2 <= max_f2
                Paint circle (mm): cat_colors$#[cat], f1, f2, 0.42
            endif
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "F2 (Hz)"
    Text bottom: "no", "F1 (Hz)"
    Text top: "no", "F1 / F2 Feature Space | coloured by predicted category"

    # ActivationList-derived, temperature-shaped category weights.
    Select outer viewport: 4, 8, 5.58, 7.18
    Select inner viewport: 4.45, 7.70, 5.84, 6.94
    Axes: 0, max_time, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time, 0, 1.05

    Colour: cat_colors$#[1]
    Line width: 1.5
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 1]
        p_next = viz_softmax#[i*4 + 1]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor

    Colour: cat_colors$#[2]
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 2]
        p_next = viz_softmax#[i*4 + 2]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor

    Colour: cat_colors$#[3]
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 3]
        p_next = viz_softmax#[i*4 + 3]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor

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
    Text left: "yes", "Weight"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Temperature-Shaped Category Weights | not calibrated probabilities"

    # === Shared legend ===
    Select outer viewport: 0, 8, 7.28, 7.68
    Select inner viewport: 0.60, 7.70, 7.34, 7.62
    Axes: 0, 1, 0, 1
    Font size: 6

    Paint rectangle: cat_colors$#[1], 0.02, 0.045, 0.38, 0.62
    Colour: "Black"
    Text: 0.055, "left", 0.50, "half", "Vowel"
    Paint rectangle: cat_colors$#[2], 0.20, 0.225, 0.38, 0.62
    Text: 0.235, "left", 0.50, "half", "Fricative"
    Paint rectangle: cat_colors$#[3], 0.42, 0.445, 0.38, 0.62
    Text: 0.455, "left", 0.50, "half", "Silence"
    Paint rectangle: cat_colors$#[4], 0.62, 0.645, 0.38, 0.62
    Text: 0.655, "left", 0.50, "half", "Other"

    # === Summary strip ===
    Select outer viewport: 0, 8, 7.82, 8.50
    Select inner viewport: 0.60, 7.70, 7.88, 8.44
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Labels##  vowel " + fixed$(100 * count_vowel / rows_target, 1) + "\% | fricative " + fixed$(100 * count_fricative / rows_target, 1) + "\% | silence " + fixed$(100 * count_silence / rows_target, 1) + "\% | other " + fixed$(100 * count_other / rows_target, 1) + "\% | formants valid " + fixed$(100 * nValidF / rows_target, 1) + "\% "
    summary2$ = "##Control##  rate " + fixed$(vibrato_rate_hz, 2) + " Hz | depth " + fixed$(vibrato_depth_ms, 2) + " ms | threshold " + fixed$(confidence_threshold, 2) + " | temperature " + fixed$(temperature, 2) + " | effect strength " + fixed$(effect_strength, 2)
    summary3$ = "##Output##  raw mask peak " + fixed$(rawPeak, 3) + " | scale " + fixed$(maskScale, 3) + " | " + vowelOutputState$ + " | stereo width " + fixed$(stereo_width, 2) + " | " + fixed$(vizOutDur, 2) + " s | peak " + fixed$(vizOutPeak, 3)
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
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

# v1.2 fix 11: ALWAYS remove the channel copies. v1.1 cleaned them up
# only inside this branch, so running with the drawing off left two
# Sound objects behind on every run.
@safeRemove: viz_left
@safeRemove: viz_right

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