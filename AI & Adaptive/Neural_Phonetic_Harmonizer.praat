# ============================================================
# Praat AudioTools - Neural_Phonetic_Harmonizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phonetic Harmonizer - Adaptive pitch shifting per
#   phonetic class using FFNet classification.
#
# Changelog v0.6 (2026):
#   - FIX (critical): harmony voices were MONOTONE. Each voice built
#     a flat 100 Hz PitchTier and multiplied THAT by the interval
#     ratio, never extracting the sound's own pitch -- every voice
#     was resynthesized at a constant ~100*ratio Hz, destroying the
#     input's intonation (Detuned Unison = two flat drones at
#     ~99/101 Hz). v0.6 extracts the actual pitch tier from the
#     Manipulation and scales it, so voices follow the sung contour.
#     (Unvoiced material passes through unshifted -- PSOLA has no
#     pulses there; the class gains still apply.)
#   - FIX (critical): the class weights never came from the
#     classifier. "To ActivationList: 1" returns the HIDDEN layer
#     (16 units here), so the softmax ran over 4 arbitrary hidden
#     neurons. Layer 2 (the output layer) is now used -- verified
#     empirically on Praat 6.4.42.
#   - FIX (critical): output columns are ordered ALPHABETICALLY by
#     category (consonant, other, silence, vowel), not in the
#     assumed vowel/consonant/other/silence order -- every weight
#     read the wrong class. Columns are now mapped by name, built
#     from the classes actually present.
#   - FIX: inputs missing a class (e.g. a sung vowel with no
#     consonant or silence frames) produced an FFNet with fewer
#     output columns; reading column 4 returned undefined and
#     silently poisoned the softmax. Absent classes now get -1e9
#     activation (softmax ~0); if fewer than 2 classes are present
#     the net is skipped and the rule-based labels are used
#     directly.
#   - Class distribution now reported in the info window.
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Fixed Formula object references
#   - Added preset name to output
#   - Added visualization
#
# Changelog v0.5 (2026):
#   - FIX (critical, 5 sites): Object_<id>(x) Formula time-paren
#     reads replaced with object[<id>, 1, col] indexed reads.
#     v0.4's pattern:
#       Formula: "Object_" + voice1Str$ + "(x) * <gain>"
#     resolves <id> by name lookup at parse time. Works in modern
#     Praat by accident (object IDs ARE valid identifier names),
#     but is the same fragility pattern flagged throughout
#     AudioTools. v0.5 uses the lowercase indexed form.
#
#   - ARCHITECTURAL FIX: v0.4's wet_mix synthesis stepped through
#     gains per-frame (one Formula (part) call per 10ms frame).
#     This created audible discontinuities at frame boundaries
#     (a 100Hz click structure, partly masked by the smoothing
#     pass on weight vectors but not eliminated). v0.5 builds a
#     3xnFrames "weight matrix" from the smoothed weights times
#     their respective levels, then synthesizes wet_mix with a
#     SINGLE Formula on the full Sound that linearly interpolates
#     between bracketing frame centers per-sample. Result is:
#     (a) sample-accurate gain transitions (no frame clicks),
#     (b) much faster (1 Formula call instead of nFrames * 1-2),
#     (c) cleaner code (~50 lines collapse to ~15).
#
#   - PORTABILITY: The pattern Formula at line 526 used a nested
#     inline if/fi conditional to clamp to [0,1]. Now uses
#     max(0, min(1, self)) — equivalent math, single-pass.
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

# ============================================================
# Changelog v0.7 (2026):
#
#   AUDIO CHANGES everywhere. Two of these are structural.
#
#   CRITICAL 1 - Consonant_interval could not act on a single frame it
#     was named for. The consonant rule REQUIRED f0 <= 0:
#       elsif iv > silence and hnr < fricative_max and f0 <= 0
#     so every consonant-class frame was unvoiced by definition, while
#     the entire harmony engine works by scaling PitchTier points -
#     which unvoiced regions do not have. The class was defined as
#     "material with no pitch" and the control tried to transpose it.
#     Dark Consonants asked for -12 semitones and delivered an almost
#     unshifted copy of the consonant into the wet path; -12, -5, +7
#     and +12 were indistinguishable at the core of any consonant.
#     v0.7 drops the f0 <= 0 requirement, so the class is now
#     low-harmonicity material whether voiced or not. Voiced fricatives
#     and nasals now fall in it AND can be transposed. The run reports
#     how many consonant-class frames are voiced, i.e. how much of the
#     class the interval can actually reach - it was structurally 0
#     before. Genuinely unvoiced frames still pass through unshifted
#     and are governed by Consonant_level alone; that is a property of
#     PitchTier harmonisation, not something this fix removes.
#
#   CRITICAL 2 - Scale peak: 0.9 on the wet mix erased the class
#     levels. The three levels were applied correctly and then the
#     whole wet path was renormalised to a fixed peak, so on
#     single-class material Vowel_level 0.1 and 0.9 produced the same
#     wet loudness. Multiplying all three levels by any common factor
#     changed nothing at all. Removed; the only gain stage left is a
#     CONDITIONAL limiter on the finished output.
#
#   3 - MFCC is aligned in time with everything else. v0.6 read MFCC by
#     FRAME NUMBER while querying pitch, intensity, HNR and formants at
#     a hand-computed (i - 0.5) * frame_step, and the two are not the
#     same instant - the 25 ms MFCC window puts frame 1 well past
#     5 ms. Worse, iM = min(i, nFrames_mfcc) repeated the LAST MFCC
#     frame for the whole tail once the control grid outran it. The
#     frame index is now derived from the MFCC object's own x1 and dx,
#     and the analysis time is clamped inside the sound.
#
#   4 - Formant validity is tracked. Undefined formants were filled
#     with 500 / 1500 Hz - canonical vowel values - and the vowel rule
#     only asks F1 > 300, so a frame whose formant analysis FAILED
#     could be labelled a vowel because of the fallback, and the FFNet
#     saw a textbook vowel rather than a missing measurement. The
#     vowel rule now requires valid formants, and the feature fill is
#     the file's own valid mean.
#
#   5 - The silence threshold is relative (max intensity - 35 dB). A
#     fixed 45 dB SPL cut meant the same performance, attenuated,
#     reclassified as silence.
#
#   6 - Random_seed added (0 = unpredictable). FFNet initialisation
#     and training are stochastic; the generator is returned to its
#     safe state afterwards.
#
#   7 - Silent input rejected before analysis.
#
#   8 - Validation. The form says "0-1" but `positive` does not bound
#     to 1, so Wet_dry_mix = 1.5 gave dry_gain = -0.5 - a phase
#     inversion of the dry path, not a mix - and Stereo_width > 2
#     could drive a channel component negative.
#
#   9 - The formant ceiling follows Nyquist; a fixed 5500 Hz is above
#     it on any file below 11 kHz.
#
#   10 - Documentation:
#     - This is per-file FFNet distillation of heuristic rules: the
#       rules make the labels, the net trains on those frames, is
#       tested on the same frames, and smooths the same labels. There
#       is no corpus, no held-out set and no ground truth. It is not a
#       phonetic recogniser.
#     - Stereo width comes from OPPOSING DRY/WET BALANCES, not from
#       placing the harmony voices at different positions - both
#       channels use the same wet mix.
#     - Multichannel input is downmixed to mono; the stereo output is
#       synthesised.
#
# ============================================================

form Phonetic Harmonizer v0.7  (per-file FFNet class distillation)
    optionmenu Preset: 1
        option Manual
        option Octave Chorus
        option Fifth Harmony
        option Vowel Choir
        option Dark Consonants
        option Shimmer
        option Detuned Unison
        option Major Chord
        option Minor Chord
    real Vowel_interval_1 7.0
    real Vowel_interval_2 0.0
    real Consonant_interval -5.0
    real Other_interval 4.0
    real Vowel_level 0.7
    real Consonant_level 0.5
    real Other_level 0.6
    real Wet_dry_mix 0.5
    positive Smoothing_ms 20
    positive Temperature 0.3
    real Stereo_width 0.5
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Consonant_interval only reaches VOICED consonant frames: harmony is
# produced by scaling PitchTier points, and unvoiced material has none.
# Those frames pass through unshifted and are governed by
# Consonant_level. The run reports how much of the class is voiced.
# Stereo_width < 0 gives mono. Width comes from opposing dry/wet
# balances, not from placing the voices apart - both channels share one
# wet mix. Multichannel input is downmixed to mono.
if stereo_width < 0
    stereo_output = 0
    stereo_width = 0
else
    stereo_output = 1
endif

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Octave Chorus
    vowel_interval_1 = 12.0
    vowel_interval_2 = 0.0
    consonant_interval = 12.0
    other_interval = 12.0
    vowel_level = 0.6
    consonant_level = 0.4
    other_level = 0.5
    wet_dry_mix = 0.4
    temperature = 0.3
    stereo_width = 0.6
    presetName$ = "OctaveChorus"
elsif preset = 3
    # Fifth Harmony
    vowel_interval_1 = 7.0
    vowel_interval_2 = 0.0
    consonant_interval = 7.0
    other_interval = 7.0
    vowel_level = 0.7
    consonant_level = 0.5
    other_level = 0.6
    wet_dry_mix = 0.5
    temperature = 0.25
    stereo_width = 0.5
    presetName$ = "FifthHarmony"
elsif preset = 4
    # Vowel Choir
    vowel_interval_1 = 7.0
    vowel_interval_2 = 12.0
    consonant_interval = 0.0
    other_interval = 4.0
    vowel_level = 0.9
    consonant_level = 0.2
    other_level = 0.4
    wet_dry_mix = 0.6
    temperature = 0.2
    stereo_width = 0.7
    presetName$ = "VowelChoir"
elsif preset = 5
    # Dark Consonants
    vowel_interval_1 = 0.0
    vowel_interval_2 = 0.0
    consonant_interval = -12.0
    other_interval = -7.0
    vowel_level = 0.3
    consonant_level = 0.8
    other_level = 0.6
    wet_dry_mix = 0.5
    temperature = 0.35
    stereo_width = 0.4
    presetName$ = "DarkConsonants"
elsif preset = 6
    # Shimmer
    vowel_interval_1 = 12.0
    vowel_interval_2 = 19.0
    consonant_interval = 12.0
    other_interval = 12.0
    vowel_level = 0.5
    consonant_level = 0.3
    other_level = 0.4
    wet_dry_mix = 0.4
    temperature = 0.2
    stereo_width = 0.8
    presetName$ = "Shimmer"
elsif preset = 7
    # Detuned Unison
    vowel_interval_1 = 0.15
    vowel_interval_2 = -0.15
    consonant_interval = 0.1
    other_interval = 0.12
    vowel_level = 0.8
    consonant_level = 0.6
    other_level = 0.7
    wet_dry_mix = 0.5
    temperature = 0.3
    stereo_width = 0.9
    presetName$ = "DetunedUnison"
elsif preset = 8
    # Major Chord
    vowel_interval_1 = 4.0
    vowel_interval_2 = 7.0
    consonant_interval = 4.0
    other_interval = 7.0
    vowel_level = 0.7
    consonant_level = 0.5
    other_level = 0.6
    wet_dry_mix = 0.5
    temperature = 0.25
    stereo_width = 0.6
    presetName$ = "MajorChord"
elsif preset = 9
    # Minor Chord
    vowel_interval_1 = 3.0
    vowel_interval_2 = 7.0
    consonant_interval = 3.0
    other_interval = 7.0
    vowel_level = 0.7
    consonant_level = 0.5
    other_level = 0.6
    wet_dry_mix = 0.5
    temperature = 0.25
    stereo_width = 0.6
    presetName$ = "MinorChord"
else
    presetName$ = "Manual"
endif

# Hidden parameters
frame_step_sec = 0.01
hidden_units = 16
training_iterations = 1000
learning_rate = 0.001
vowel_hnr_threshold = 5.0
fricative_hnr_max = 3.0

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
writeInfoLine: "=== Phonetic Harmonizer v0.7 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Vowel: ", vowel_interval_1, " / ", vowel_interval_2, " st"
appendInfoLine: "Consonant: ", consonant_interval, " st | Other: ", other_interval, " st"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_mix * 100, 0), "%"
if stereo_output
    appendInfoLine: "Output: Stereo (width ", fixed$(stereo_width * 100, 0), "%)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

selectObject: sound
workSnd = Convert to mono

# ============================================
# VALIDATION  (v0.7 fix 8)
# ============================================
warnLines$ = ""
if vowel_level < 0
    vowel_level = 0
    warnLines$ = warnLines$ + "  ! Vowel_level < 0 -> 0" + newline$
endif
if vowel_level > 1
    vowel_level = 1
    warnLines$ = warnLines$ + "  ! Vowel_level > 1 -> 1" + newline$
endif
if consonant_level < 0
    consonant_level = 0
    warnLines$ = warnLines$ + "  ! Consonant_level < 0 -> 0" + newline$
endif
if consonant_level > 1
    consonant_level = 1
    warnLines$ = warnLines$ + "  ! Consonant_level > 1 -> 1" + newline$
endif
if other_level < 0
    other_level = 0
    warnLines$ = warnLines$ + "  ! Other_level < 0 -> 0" + newline$
endif
if other_level > 1
    other_level = 1
    warnLines$ = warnLines$ + "  ! Other_level > 1 -> 1" + newline$
endif
if wet_dry_mix < 0
    wet_dry_mix = 0
    warnLines$ = warnLines$ + "  ! Wet_dry_mix < 0 -> 0" + newline$
endif
if wet_dry_mix > 1
    wet_dry_mix = 1
    warnLines$ = warnLines$ +
        ... "  ! Wet_dry_mix > 1 inverts the dry path's phase -> 1" + newline$
endif
if stereo_width > 1
    stereo_width = 1
    warnLines$ = warnLines$ +
        ... "  ! Stereo_width > 1 can drive a channel component negative -> 1" + newline$
endif
if smoothing_ms < 0
    smoothing_ms = 0
    warnLines$ = warnLines$ + "  ! Smoothing_ms < 0 -> 0" + newline$
endif
if temperature <= 0
    temperature = 0.01
    warnLines$ = warnLines$ + "  ! Temperature must be > 0 -> 0.01" + newline$
endif

# v0.7 fix 7: a silent input yields a single silence class, a wet mix
# of zeros, and then peak normalisation of nothing.
selectObject: workSnd
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 1e-6
    removeObject: workSnd
    exitScript: "The selected Sound is silent (or near-silent); nothing to harmonise."
endif

# v0.7 fix 6: FFNet initialisation and training are stochastic.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif
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
# v0.7 fix 9: a fixed 5500 Hz ceiling is above Nyquist on any file
# below 11 kHz.
maxFormantHz = 5500
if maxFormantHz > fs / 2 * 0.9
    maxFormantHz = fs / 2 * 0.9
endif
formant_obj = To Formant (burg): 0, 5, maxFormantHz, 0.025, 50

selectObject: workSnd
mfcc_obj = To MFCC: 12, 0.025, frame_step_sec, 100, 100, 0

selectObject: workSnd
hnr_obj = To Harmonicity (cc): frame_step_sec, 75, 0.1, 1.0

selectObject: mfcc_obj
# v0.7 fix 5: relative to the file, not an absolute dB SPL cut. The
# same performance attenuated by 20 dB used to reclassify as silence.
selectObject: intensity_obj
maxIntDb = Get maximum: 0, 0, "Parabolic"
if maxIntDb = undefined
    maxIntDb = 60
endif
silence_threshold = maxIntDb - 35
if silence_threshold < 5
    silence_threshold = 5
endif

# v0.7 fix 4: a neutral fill from the file's own valid formants.
formantValid# = zero#(nFrames)
sumFa = 0
sumFb = 0
nValidF = 0
for i from 1 to nFrames
    tv = (i - 0.5) * frame_step_sec
    if tv > duration - frame_step_sec / 2
        tv = duration - frame_step_sec / 2
    endif
    if tv < 0
        tv = 0
    endif
    selectObject: formant_obj
    fa = Get value at time: 1, tv, "Hertz", "Linear"
    selectObject: formant_obj
    fb = Get value at time: 2, tv, "Hertz", "Linear"
    if fa <> undefined and fb <> undefined
        nValidF = nValidF + 1
        sumFa = sumFa + fa
        sumFb = sumFb + fb
    endif
endfor
if nValidF > 0
    fillF1 = sumFa / nValidF
    fillF2 = sumFb / nValidF
else
    fillF1 = 500
    fillF2 = 1500
endif
appendInfoLine: "  Formants valid in ", nValidF, "/", nFrames, " frames"

nConsVoiced = 0
nConsTotal = 0

nFrames_mfcc = Get number of frames
if nFrames_mfcc < 1
    exitScript: "MFCC analysis produced no frames; the input is too short for a 25 ms window."
endif
selectObject: mfcc_obj
mfccT1 = Get time from frame number: 1
if nFrames_mfcc > 1
    selectObject: mfcc_obj
    mfccT2 = Get time from frame number: 2
    mfccDx = mfccT2 - mfccT1
else
    mfccDx = frame_step_sec
endif
if mfccDx <= 0
    mfccDx = frame_step_sec
endif

for i from 1 to nFrames
    # v0.7 fix 3: one time for every query, clamped inside the sound.
    t = (i - 0.5) * frame_step_sec
    if t > duration - frame_step_sec / 2
        t = duration - frame_step_sec / 2
    endif
    if t < 0
        t = 0
    endif
    frame_time#[i] = t
    
    # v0.7 fix 3: derive the MFCC frame from the object's own x1/dx
    # instead of assuming frame i is centred at (i-0.5)*step. v0.6 also
    # used min(i, nFrames_mfcc), which repeated the LAST MFCC frame for
    # the entire tail whenever the control grid outran the analysis.
    iM = round((t - mfccT1) / mfccDx) + 1
    if iM < 1
        iM = 1
    endif
    if iM > nFrames_mfcc
        iM = nFrames_mfcc
    endif
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
    selectObject: formant_obj
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    # v0.7 fix 4: track VALIDITY. v0.6 filled undefined formants with
    # 500 / 1500 Hz - canonical vowel values - and the vowel rule only
    # asks F1 > 300, so a frame whose formant analysis FAILED could be
    # labelled a vowel because of the fallback. The fill is now the
    # file's own valid mean and it is never enough on its own.
    if f1 = undefined or f2 = undefined
        formantValid#[i] = 0
        if f1 = undefined
            f1 = fillF1
        endif
        if f2 = undefined
            f2 = fillF2
        endif
    else
        formantValid#[i] = 1
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
    elsif formantValid#[i] = 1 and hnr > vowel_hnr_threshold and f0 > 0 and f1 > 300
        cat_vowel#[i] = 1
    # v0.7 CRITICAL 1: the f0 <= 0 requirement is gone. It made every
    # consonant-class frame unvoiced BY DEFINITION, and the harmony
    # engine works by scaling PitchTier points, which unvoiced regions
    # do not have - so Consonant_interval could not reach a single
    # frame of the class it names. The class is now low-harmonicity
    # material whether voiced or not, so voiced fricatives and nasals
    # land in it and can actually be transposed.
    elsif iv > silence_threshold and hnr < fricative_hnr_max
        cat_consonant#[i] = 1
        if f0 > 0
            nConsVoiced = nConsVoiced + 1
        endif
        nConsTotal = nConsTotal + 1
    else
        cat_other#[i] = 1
    endif
endfor

removeObject: pitch_obj, intensity_obj, formant_obj, mfcc_obj, hnr_obj

appendInfoLine: "  ", nFrames, " frames analyzed"
appendInfoLine: "  Consonant class: ", nConsVoiced, "/", nConsTotal,
    ... " frames voiced (only these can be transposed;"
appendInfoLine: "    unvoiced ones pass through and follow Consonant_level)"
appendInfoLine: "  Seed: ", seedLabel$
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif

# ============================================
# NORMALIZE FEATURES
# ============================================

appendInfoLine: "Normalizing features..."

# Helper procedure-like normalization
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
# v0.5: clamp pattern values to [0,1]. Was using nested
# inline if/fi; now uses max(min) for clarity and single-pass.
Formula: "max(0, min(1, self))"

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

# v0.6: class presence + alphabetical column mapping. Praat's FFNet
# orders output nodes ALPHABETICALLY over the categories that are
# actually present: consonant, other, silence, vowel. Columns are
# assigned by name; absent classes get no column (activation -1e9,
# softmax ~0). Verified empirically on Praat 6.4.42.
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
appendInfoLine: "  Classes: vowel ", fixed$(100 * nVowelFr / nFrames, 0),
    ... "% | consonant ", fixed$(100 * nConsFr / nFrames, 0),
    ... "% | other ", fixed$(100 * nOtherFr / nFrames, 0),
    ... "% | silence ", fixed$(100 * nSilFr / nFrames, 0), "%"

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
    # Degenerate input (a single class): an FFNet with one output
    # is meaningless -- use the rule-based labels directly.
    appendInfoLine: "  Only ", nClassesPresent, " class present; skipping FFNet, using rule-based weights"
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
    # v0.6: layer 2 = the OUTPUT layer of this one-hidden-layer net.
    # Layer 1 is the hidden layer -- v0.5 softmaxed 4 of the 16
    # hidden neurons, so the trained classification never reached
    # the mixer at all.
    To ActivationList: 2
    activations = selected("ActivationList")
    To Matrix
    activation_matrix = selected("Matrix")

    for i from 1 to nFrames
        selectObject: activation_matrix
        if col_vowel > 0
            a1 = Get value in cell: i, col_vowel
        else
            a1 = -1e9
        endif
        if col_consonant > 0
            a2 = Get value in cell: i, col_consonant
        else
            a2 = -1e9
        endif
        if col_other > 0
            a3 = Get value in cell: i, col_other
        else
            a3 = -1e9
        endif
        if col_silence > 0
            a4 = Get value in cell: i, col_silence
        else
            a4 = -1e9
        endif
        if a1 = undefined
            a1 = -1e9
        endif
        if a2 = undefined
            a2 = -1e9
        endif
        if a3 = undefined
            a3 = -1e9
        endif
        if a4 = undefined
            a4 = -1e9
        endif
        
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
endif

# ============================================
# SMOOTH WEIGHTS
# ============================================

smooth_frames = round(smoothing_ms / (frame_step_sec * 1000))
if smooth_frames < 1
    smooth_frames = 1
endif

weight_vowel_smooth# = zero#(nFrames)
weight_consonant_smooth# = zero#(nFrames)
weight_other_smooth# = zero#(nFrames)

for i from 1 to nFrames
    i1 = max(1, i - smooth_frames)
    i2 = min(nFrames, i + smooth_frames)
    n = i2 - i1 + 1
    
    sum_v = 0
    sum_c = 0
    sum_o = 0
    
    for k from i1 to i2
        sum_v += weight_vowel#[k]
        sum_c += weight_consonant#[k]
        sum_o += weight_other#[k]
    endfor
    
    weight_vowel_smooth#[i] = sum_v / n
    weight_consonant_smooth#[i] = sum_c / n
    weight_other_smooth#[i] = sum_o / n
endfor

# ============================================
# CREATE PITCH-SHIFTED VOICES
# ============================================

appendInfoLine: "Creating harmony voices..."

# Voice 1: Vowel interval 1
if vowel_interval_1 <> 0
    selectObject: workSnd
    manip1 = To Manipulation: 0.01, 75, 600
    # v0.6: scale the sound's OWN pitch tier. The old code built a
    # flat 100 Hz tier, so every voice came out monotone.
    Extract pitch tier
    pt1 = selected("PitchTier")
    int1Str$ = string$(vowel_interval_1)
    Formula: "self * 2^(" + int1Str$ + "/12)"
    selectObject: manip1
    plusObject: pt1
    Replace pitch tier
    selectObject: manip1
    voice1 = Get resynthesis (overlap-add)
    removeObject: manip1, pt1
else
    selectObject: workSnd
    voice1 = Copy: "v1"
endif
selectObject: voice1
Rename: "HarmVoice1"

# Voice 2: Vowel interval 2
if vowel_interval_2 <> 0
    selectObject: workSnd
    manip2 = To Manipulation: 0.01, 75, 600
    # v0.6: scale the sound's OWN pitch tier. The old code built a
    # flat 100 Hz tier, so every voice came out monotone.
    Extract pitch tier
    pt2 = selected("PitchTier")
    int2Str$ = string$(vowel_interval_2)
    Formula: "self * 2^(" + int2Str$ + "/12)"
    selectObject: manip2
    plusObject: pt2
    Replace pitch tier
    selectObject: manip2
    voice2 = Get resynthesis (overlap-add)
    removeObject: manip2, pt2
    selectObject: voice2
    Rename: "HarmVoice2"
    has_voice2 = 1
else
    has_voice2 = 0
    voice2 = 0
endif

# Voice 3: Consonant interval
if consonant_interval <> 0
    selectObject: workSnd
    manip3 = To Manipulation: 0.01, 75, 600
    # v0.6: scale the sound's OWN pitch tier. The old code built a
    # flat 100 Hz tier, so every voice came out monotone.
    Extract pitch tier
    pt3 = selected("PitchTier")
    int3Str$ = string$(consonant_interval)
    Formula: "self * 2^(" + int3Str$ + "/12)"
    selectObject: manip3
    plusObject: pt3
    Replace pitch tier
    selectObject: manip3
    voice3 = Get resynthesis (overlap-add)
    removeObject: manip3, pt3
else
    selectObject: workSnd
    voice3 = Copy: "v3"
endif
selectObject: voice3
Rename: "HarmVoice3"

# Voice 4: Other interval
if other_interval <> 0
    selectObject: workSnd
    manip4 = To Manipulation: 0.01, 75, 600
    # v0.6: scale the sound's OWN pitch tier. The old code built a
    # flat 100 Hz tier, so every voice came out monotone.
    Extract pitch tier
    pt4 = selected("PitchTier")
    int4Str$ = string$(other_interval)
    Formula: "self * 2^(" + int4Str$ + "/12)"
    selectObject: manip4
    plusObject: pt4
    Replace pitch tier
    selectObject: manip4
    voice4 = Get resynthesis (overlap-add)
    removeObject: manip4, pt4
else
    selectObject: workSnd
    voice4 = Copy: "v4"
endif
selectObject: voice4
Rename: "HarmVoice4"

# ============================================
# MIX VOICES (v0.5: sample-accurate, single Formula)
# ============================================

appendInfoLine: "Mixing voices..."

# v0.5 architecture: Build a 3xnFrames weight matrix from the smoothed
# weights * level, then run a SINGLE Formula on wet_mix that interpolates
# linearly between bracketing frame centers per-sample. Replaces the
# v0.4 per-frame Formula (part) loop, eliminating frame-boundary clicks.

# 1. Build the weight matrix.
#    Row 1 = vowel * vowel_level
#    Row 2 = consonant * consonant_level
#    Row 3 = other * other_level
weightMat = Create simple Matrix: "voice_weights", 3, nFrames, "0"
selectObject: weightMat
for i from 1 to nFrames
    Set value: 1, i, weight_vowel_smooth#[i] * vowel_level
    Set value: 2, i, weight_consonant_smooth#[i] * consonant_level
    Set value: 3, i, weight_other_smooth#[i] * other_level
endfor

# 2. Pre-compute interpolation constants:
#   For sample col (1-based), time t = (col-0.5)/fs.
#   Frame centers are at (i-0.5)*step.  Setting i = (t/step + 0.5):
#     fIdxF = col*<a> + <b>  where  a = 1/(fs*step), b = 0.5 - 0.5*a
#   fLo = floor(fIdxF), clamped to [1, nFrames-1].
#   frac = fIdxF - fLo.  fHi = fLo + 1.
a_const = 1 / (fs * frame_step_sec)
b_const = 0.5 - 0.5 * a_const
a_str$ = fixed$(a_const, 12)
b_str$ = fixed$(b_const, 12)
nFm1 = nFrames - 1
nFm1_str$ = string$(nFm1)

wM_str$ = string$(weightMat)
v1Str$ = string$(voice1)
v3Str$ = string$(voice3)
v4Str$ = string$(voice4)

# Sub-expressions (factored for readability — Praat re-evaluates each
# occurrence; modern Praat's bytecode-level Formula evaluation handles
# this fast, no actual perf concern).
fIdxF_$ = "(col*" + a_str$ + "+" + b_str$ + ")"
fLo_$   = "max(1,min(" + nFm1_str$ + ",floor(" + fIdxF_$ + ")))"
fHi_$   = "(" + fLo_$ + "+1)"
frac_$  = "max(0,min(1," + fIdxF_$ + "-" + fLo_$ + "))"

# Per-channel interpolated gain reads
gainV_$ = "(object[" + wM_str$ + ",1," + fLo_$ + "]*(1-" + frac_$ + ")+object[" + wM_str$ + ",1," + fHi_$ + "]*" + frac_$ + ")"
gainC_$ = "(object[" + wM_str$ + ",2," + fLo_$ + "]*(1-" + frac_$ + ")+object[" + wM_str$ + ",2," + fHi_$ + "]*" + frac_$ + ")"
gainO_$ = "(object[" + wM_str$ + ",3," + fLo_$ + "]*(1-" + frac_$ + ")+object[" + wM_str$ + ",3," + fHi_$ + "]*" + frac_$ + ")"

# 3. Allocate wet_mix and run the single mixing Formula.
wet_mix = Create Sound from formula: "Wet", 1, 0, duration, fs, "0"
selectObject: wet_mix
Formula: "object[" + v1Str$ + ",1,col]*" + gainV_$
    ... + "+object[" + v3Str$ + ",1,col]*" + gainC_$
    ... + "+object[" + v4Str$ + ",1,col]*" + gainO_$

# 4. If voice2 is present, add its contribution at 0.7 * vowel_gain.
if has_voice2
    v2Str$ = string$(voice2)
    selectObject: wet_mix
    Formula: "self + object[" + v2Str$ + ",1,col]*" + gainV_$ + "*0.7"
endif

removeObject: weightMat, voice1, voice3, voice4
if has_voice2
    removeObject: voice2
endif

# ============================================
# FINAL MIX
# ============================================

appendInfoLine: "Creating final mix..."

# v0.7 CRITICAL 2: NO renormalisation of the wet path. v0.6 applied
# the three class levels correctly and then rescaled the whole wet mix
# to a fixed peak of 0.9, so on single-class material Vowel_level 0.1
# and 0.9 gave the same wet loudness, and scaling all three levels by
# a common factor changed nothing. The only gain stage left is the
# conditional limiter on the finished output.
selectObject: wet_mix
Rename: "WetMix"
wetMixId = selected("Sound")
wetMixStr$ = string$(wetMixId)
workSndStr$ = string$(workSnd)

if stereo_output
    dry_gain = 1 - wet_dry_mix
    wet_gain = wet_dry_mix
    
    left_dry = dry_gain * (1 - stereo_width * 0.5)
    left_wet = wet_gain * (1 + stereo_width * 0.5)
    right_dry = dry_gain * (1 + stereo_width * 0.5)
    right_wet = wet_gain * (1 - stereo_width * 0.5)
    
    ldStr$ = string$(left_dry)
    lwStr$ = string$(left_wet)
    rdStr$ = string$(right_dry)
    rwStr$ = string$(right_wet)
    
    # v0.5: object[<id>, 1, col] indexed reads instead of Object_<id>(x).
    # workSnd, wet_mix, and the L/R copies share the same fs and xmin=0,
    # so col indexing maps directly between them.
    selectObject: workSnd
    left_ch = Copy: "Left"
    selectObject: left_ch
    Formula: "self * " + ldStr$ + " + object[" + wetMixStr$ + ",1,col] * " + lwStr$
    
    selectObject: workSnd
    right_ch = Copy: "Right"
    selectObject: right_ch
    Formula: "self * " + rdStr$ + " + object[" + wetMixStr$ + ",1,col] * " + rwStr$
    
    selectObject: left_ch
    plusObject: right_ch
    finalOut = Combine to stereo
    Rename: sound_name$ + "_harmonized_" + presetName$
    
    removeObject: left_ch, right_ch
else
    dry_gain = 1 - wet_dry_mix
    wet_gain = wet_dry_mix
    dgStr$ = string$(dry_gain)
    wgStr$ = string$(wet_gain)
    
    # v0.5: object[<id>, 1, col] indexed read.
    selectObject: workSnd
    finalOut = Copy: "Final"
    selectObject: finalOut
    Formula: "self * " + dgStr$ + " + object[" + wetMixStr$ + ",1,col] * " + wgStr$
    Rename: sound_name$ + "_harmonized_" + presetName$
endif

selectObject: finalOut
# v0.7 CRITICAL 2: a CONDITIONAL limiter, so the class levels and
# Wet_dry_mix actually determine the output loudness.
finalPeakChk = Get absolute extremum: 0, 0, "None"
if finalPeakChk > 0.99
    Scale peak: 0.99
endif

# v0.7 fix 6: all stochastic work is done.
random_initializeSafelyAndUnpredictably ()

# ============================================
# CLEANUP
# ============================================

removeObject: workSnd, wet_mix

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phonetic Harmonizer v0.7: " + sound_name$ + " [" + presetName$ + "]"
    
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
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: finalOut
    Colour: "{0.4, 0.6, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Phonetic weights
    Select outer viewport: 0, 8, 2.7, 4.2
    Select inner viewport: 0.6, 7.6, 2.9, 4.1
    
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
    
    # Vowel weights
    Colour: "{0.8, 0.3, 0.3}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_vowel_smooth#[i-1], t2, weight_vowel_smooth#[i]
    endfor
    
    # Consonant weights
    Colour: "{0.3, 0.5, 0.8}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_consonant_smooth#[i-1], t2, weight_consonant_smooth#[i]
    endfor
    
    # Other weights
    Colour: "{0.5, 0.7, 0.3}"
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, weight_other_smooth#[i-1], t2, weight_other_smooth#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Weight"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 8
    Colour: "{0.8, 0.3, 0.3}"
    Text: 0.2, "centre", 0.5, "half", "— Vowel (" + fixed$(vowel_interval_1, 1) + "/" + fixed$(vowel_interval_2, 1) + " st)"
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.5, "centre", 0.5, "half", "— Consonant (" + fixed$(consonant_interval, 1) + " st)"
    Colour: "{0.5, 0.7, 0.3}"
    Text: 0.8, "centre", 0.5, "half", "— Other (" + fixed$(other_interval, 1) + " st)"
    
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
n_ch = Get number of channels
out_dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(out_dur, 2), " s"
appendInfoLine: "Channels: ", n_ch

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut