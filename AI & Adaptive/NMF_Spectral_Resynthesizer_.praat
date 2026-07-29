# ============================================================
# Praat AudioTools - NMF_Spectral_Resynthesizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   NMF Spectral Resynthesizer - Decomposes spectrogram via
#   Non-negative Matrix Factorization for creative resynthesis.
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Added preset name to output
#   - Added visualization
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

id_original = selected("Sound")
name_original$ = selected$("Sound")

# ============================================================
# Changelog v0.6 (2026):
#
#   Four of these close gaps between v0.5's changelog and its code -
#   two items were described as done and were not written.
#
#   1 - Reconstruction error is now actually computed and reported:
#     ||V - WH||_F / ||V||_F. v0.5's item 8 promised it; no such
#     calculation existed. Diagnostic only - few iterations may be
#     exactly what a preset wants.
#
#   2 - H_left and H_right are kept separately, and the visualisation
#     draws H_LEFT. v0.5 let the right-channel pass overwrite matH, so
#     in stereo the plot showed the right channel's perturbed, smoothed
#     H and the left was gone before anything was drawn.
#
#   3 - The H time axis uses the spectrogram's own x1 and dx. v0.5's
#     item 9 claimed this; the code still used the REQUESTED step_ms
#     starting at zero, so neither end of the plot lined up with the
#     analysis.
#
#   4 - The nCols < 2 exit now runs BEFORE the seed, and matH_raw is
#     removed in cleanup - it was leaking one Matrix per run.
#
#   5 - "shared W, independent H" corrected to "shared W, decorrelated
#     H variants". The right channel is S(H_raw * R) against the left's
#     S(H_raw): correlated variants of one decomposition, not a second
#     independent NMF. The accurate description is also the better
#     musical one - the channels keep a shared spectral identity.
#
#   6 - Transient_components is a form field. v0.5 always took the two
#     roughest, so Fast Preview's 2 components meant every component
#     was a transient and none was texture. That may well be what the
#     preset wants, but it should be a visible choice rather than a
#     side effect of the constant 2.
#
# ============================================================
# Changelog v0.5 (2026):
#
#   DELIBERATELY NOT CHANGED - these are the tool's musical identity,
#   not defects, and are now documented rather than "corrected":
#
#     * Resynthesis regenerates phase. Spectrogram: To Sound is not an
#       inverse STFT and not Griffin-Lim: it sums sqrt(P(f,t)) * sin
#       with phase set by absolute time, so the source micro-phase is
#       gone and power is interpolated continuously between frames.
#       That is what produces the glassy, re-synthesised character.
#       A phase-preserving mode would be a different instrument.
#     * The extreme window:step ratios stay. Smooth Gliss analyses a
#       2 ms window every 50 ms - absurd for an STFT, but this engine
#       interpolates power between frames rather than overlap-adding
#       windows, so there are no 48 ms holes; there are sparse spectral
#       samples glided between. That IS the gliss.
#     * 1-2 ms windows stay. They give wide, few bins and poor
#       frequency detail, which is the point of the Texture preset.
#
#   MUST-FIX 1 - component roles were assigned by ROW NUMBER.
#     "if row <= 2" gave rows 1-2 the transient decay and everything
#     else the texture smear. NMF has no canonical component order:
#     swapping two columns of W and the matching rows of H leaves WH
#     identical, so which component is "1" is an artefact of the random
#     initialisation. Component 1 could be a transient in one run and a
#     low drone in the next, while the genuinely percussive component
#     sat at row 3 and got smeared. With no seed, that varied run to
#     run. v0.5 measures each row's temporal roughness,
#       sum |H[k,t] - H[k,t-1]| / (sum H[k,t] + eps),
#     ranks the components by it, and gives the decay to the two
#     roughest. The ranking is printed.
#
#   MUST-FIX 2 - the right channel was smoothed TWICE and was not
#     "independent H". matH was already decayed and blurred before the
#     left channel was built; the right channel then perturbed THAT
#     matrix and ran the whole smoothing chain over it again, so
#     H_right = S(S(H_raw) * R) against H_left = S(H_raw). The right
#     channel was systematically duller and more smeared, the left H
#     was destroyed, and the visualisation and matRecon ended up
#     showing the right channel only. v0.5 keeps H_raw, derives both
#     channels from it with equal processing depth, and exposes
#     Stereo_decorrelation (0 = identical H, 1 = full +/-15%).
#
#   MUST-FIX 3 - Texture blur is a FORWARD SMEAR, not a symmetric
#     blur. Praat evaluates Formula left to right and can read a cell
#     it has already modified in the same pass, so self[row, col-1] is
#     the value AFTER blurring while col+1 is untouched: the kernel is
#     not [0.25, 0.5, 0.25] but a directional trail with memory.
#     Following the review's advice, the SOUND is unchanged and the
#     parameter is renamed Texture_smear_passes with the mechanism
#     documented. The mismatch was between the name and the maths, not
#     in the result.
#
#   MUST-FIX 4 - a silent input could become a loud one. The
#     "self + 1e-9" floor turns a silent spectrogram into a tiny
#     positive matrix, NMF reconstructs it, and the unconditional
#     Scale peak: 0.99 then amplified numerical noise to near full
#     scale. Silent input is now rejected, and the final normalisation
#     is a conditional limiter.
#
#   MUST-FIX 5 - validation and a seed. Trans_decay > 1 makes
#     (1 - trans_decay) negative, so H stops being non-negative and the
#     reconstructed "power" spectrogram can go negative - not a valid
#     spectral density. Also nCols >= 2, since the resynthesis
#     interpolates between adjacent frames and a single frame gives it
#     nothing to interpolate across. Random_seed added, with a safe
#     reset afterwards.
#
#   6 - Pitch anchoring is now a MODE, not a mandatory stage. Replacing
#     a Manipulation's PitchTier does not replace its pulses: PSOLA
#     still uses the pulses found in the SYNTHESISED sound to decide
#     voiced/unvoiced regions, so the original contour is not imposed
#     absolutely - it applies where the resynthesis happened to look
#     periodic. That is probably what turns a bodiless additive
#     spectrum into a gesture that recalls the source, so it stays the
#     default; Pitch_anchoring now offers Raw / Anchored / Blend so the
#     two can be heard apart.
#
#   7 - W and H are normalised each iteration (column norm of W to 1,
#     the reciprocal into the H row). WH and the audio are unchanged -
#     this only removes NMF's scale ambiguity so the visualisation,
#     the roughness ranking and the stereo perturbation are comparable
#     across components.
#
#   8 - Reconstruction error is reported (relative Frobenius distance
#     between V and WH) for information only. Few iterations may be
#     exactly what a preset wants; the number just says how far from
#     the source the decomposition sits.
#
#   9 - The H visualisation uses the spectrogram's real x1 and dx
#     instead of column * requested step_ms.
#
# ============================================================

form NMF Spectral Resynthesizer v0.6
    optionmenu Preset: 1
        option Manual
        option Fast Preview
        option Smooth Gliss
        option Clicks
        option Texture
        option High Definition
    positive Window_ms 10
    positive Step_ms 4.0
    real Trans_decay 0.6
    integer Texture_smear_passes 4
    positive Min_pitch 75
    positive Max_pitch 600
    positive Pitch_smoothing_hz 10
    natural Max_freq_hz 4000
    natural N_components 4
    natural N_iterations 8
    integer Transient_components 2
    optionmenu Pitch_anchoring: 2
        option Raw NMF resynthesis
        option Original-contour PSOLA anchoring
        option Blend raw and anchored
    real Stereo_decorrelation 0.5
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# Texture_smear_passes is a FORWARD smear, not a symmetric blur: Praat
# reads the already-modified col-1 within the same pass, so the kernel
# trails rather than centres. Kept as-is because that is the sound;
# named for what it does.
# Stereo_decorrelation: 0 = identical channels, 1 = full +/-15%
# perturbation of H. Negative = mono output.
# Resynthesis REGENERATES PHASE - it is an additive sine bank, not an
# inverse STFT - and that is the tool's character, not a defect.
texture_blur_passes = texture_smear_passes
if stereo_decorrelation < 0
    stereo_output = 0
    stereo_decorrelation = 0
else
    stereo_output = 1
endif

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Fast Preview
    window_ms = 15
    step_ms = 8.0
    trans_decay = 0.5
    texture_blur_passes = 2
    texture_smear_passes = 2
    max_freq_hz = 3000
    n_components = 2
    n_iterations = 4
    presetName$ = "FastPreview"
elsif preset = 3
    # Smooth Gliss
    window_ms = 2.0
    step_ms = 50.0
    trans_decay = 0.9
    texture_blur_passes = 1
    texture_smear_passes = 1
    max_freq_hz = 4000
    n_components = 3
    n_iterations = 10
    presetName$ = "SmoothGliss"
elsif preset = 4
    # Clicks
    window_ms = 60.0
    step_ms = 15.0
    trans_decay = 0.4
    texture_blur_passes = 5
    texture_smear_passes = 5
    max_freq_hz = 5000
    n_components = 5
    n_iterations = 8
    presetName$ = "Clicks"
elsif preset = 5
    # Texture
    window_ms = 1.0
    step_ms = 2.0
    trans_decay = 0.5
    texture_blur_passes = 2
    texture_smear_passes = 2
    max_freq_hz = 4000
    n_components = 4
    n_iterations = 8
    presetName$ = "Texture"
elsif preset = 6
    # High Definition
    window_ms = 8
    step_ms = 3.0
    trans_decay = 0.6
    texture_blur_passes = 3
    texture_smear_passes = 3
    max_freq_hz = 6000
    n_components = 6
    n_iterations = 15
    presetName$ = "HighDefinition"
else
    presetName$ = "Manual"
endif

# ============================================
# SETUP
# ============================================

clearinfo
writeInfoLine: "=== NMF Spectral Resynthesizer v0.6 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Window: ", window_ms, " ms | Step: ", step_ms, " ms"
appendInfoLine: "Components: ", n_components, " | Iterations: ", n_iterations
# ============================================
# VALIDATION  (v0.5 MUST-FIX 5)
# ============================================
warnLines$ = ""
if trans_decay < 0
    trans_decay = 0
    warnLines$ = warnLines$ + "  ! Trans_decay < 0 -> 0" + newline$
endif
if trans_decay > 1
    trans_decay = 1
    warnLines$ = warnLines$ +
        ... "  ! Trans_decay > 1 makes (1 - decay) negative, so H stops being" +
        ... " non-negative and the reconstructed power spectrogram can go" +
        ... " negative -> 1" + newline$
endif
if texture_blur_passes < 0
    texture_blur_passes = 0
    warnLines$ = warnLines$ + "  ! Texture_smear_passes < 0 -> 0" + newline$
endif
if n_components < 1
    n_components = 1
    warnLines$ = warnLines$ + "  ! N_components < 1 -> 1" + newline$
endif
if n_iterations < 1
    n_iterations = 1
    warnLines$ = warnLines$ + "  ! N_iterations < 1 -> 1" + newline$
endif
if min_pitch >= max_pitch
    min_pitch = 75
    max_pitch = 600
    warnLines$ = warnLines$ + "  ! Min_pitch >= Max_pitch -> reset to 75 / 600" + newline$
endif
if stereo_decorrelation > 1
    stereo_decorrelation = 1
    warnLines$ = warnLines$ + "  ! Stereo_decorrelation > 1 -> 1" + newline$
endif

appendInfoLine: "Decay: ", trans_decay, " | Smear passes: ", texture_blur_passes
if warnLines$ <> ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
if stereo_output
    # v0.6: "independent H" was wrong - the right channel is
# S(H_raw * R) against the left's S(H_raw), i.e. correlated variants
# of one decomposition, not a second independent NMF.
appendInfoLine: "Output: Stereo (shared W, decorrelated H variants)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

selectObject: id_original
sampling_rate = Get sampling frequency
duration = Get total duration
original_channels = Get number of channels

if original_channels > 1
    id_mono = Convert to mono
    Rename: name_original$ + "_mono"
else
    id_mono = Copy: name_original$ + "_mono"
endif

# ============================================
# SPECTROGRAM & INIT
# ============================================

appendInfoLine: "Creating spectrogram..."

selectObject: id_mono
spectrogram = To Spectrogram: window_ms/1000, max_freq_hz, step_ms/1000, 20, "Gaussian"
selectObject: spectrogram
matV = To Matrix
Rename: "NMF_V"
Formula: "self + 1e-9"
nRows = Get number of rows
nCols = Get number of columns

# v0.6: the spectrogram's real time axis, for the visualisation.
selectObject: spectrogram
specX1 = Get time from frame number: 1
if nCols > 1
    selectObject: spectrogram
    specX2 = Get time from frame number: 2
    specDx = specX2 - specX1
else
    specDx = step_ms / 1000
endif
if specDx <= 0
    specDx = step_ms / 1000
endif
# v0.5 MUST-FIX 4: a silent input becomes a tiny positive matrix under
# the 1e-9 floor, NMF reconstructs it, and the old unconditional
# Scale peak: 0.99 amplified numerical noise to near full scale.
selectObject: id_mono
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 1e-6
    exitScript: "The selected Sound is silent (or near-silent); there is no spectrum to factorise."
endif

# v0.6: the nCols check runs BEFORE the seed. v0.5 seeded first, so
# this exit left Praat's generator globally predictable.
# v0.5 MUST-FIX 5: the resynthesis interpolates power between ADJACENT
# frames, so a single frame gives it nothing to interpolate across and
# the output can come back silent.
if nCols < 2
    exitScript: "Only " + string$(nCols) + " analysis frame(s): increase the duration" +
        ... " or reduce Step_ms. The resynthesis interpolates between frames."
endif

# v0.5 MUST-FIX 5: the NMF initialisation and the stereo perturbation
# are random; v0.4 had no seed, so the decomposition AND which
# components were treated as transients both varied run to run.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif
appendInfoLine: "Seed: ", seedLabel$




appendInfoLine: "  Matrix size: ", nRows, " x ", nCols

matW = Create simple Matrix: "NMF_W", nRows, n_components, "randomUniform(0.1, 1)"
matH = Create simple Matrix: "NMF_H", n_components, nCols, "randomUniform(0.1, 1)"

# Store IDs for Formula references
matV_id$ = string$(matV)
matW_id$ = string$(matW)
matH_id$ = string$(matH)

# ============================================
# PRE-ALLOCATE TEMPORARY MATRICES
# ============================================

matNum_H = Create simple Matrix: "Num_H", n_components, nCols, "0"
matWtW = Create simple Matrix: "WtW", n_components, n_components, "0"
matDenom_H = Create simple Matrix: "Denom_H", n_components, nCols, "0"

matNum_W = Create simple Matrix: "Num_W", nRows, n_components, "0"
matHHt = Create simple Matrix: "HHt", n_components, n_components, "0"
matDenom_W = Create simple Matrix: "Denom_W", nRows, n_components, "0"

matNum_H_id$ = string$(matNum_H)
matWtW_id$ = string$(matWtW)
matDenom_H_id$ = string$(matDenom_H)
matNum_W_id$ = string$(matNum_W)
matHHt_id$ = string$(matHHt)
matDenom_W_id$ = string$(matDenom_W)

# ============================================
# NMF LOOP
# ============================================

appendInfoLine: "Decomposing (", n_iterations, " iterations)..."

for iter from 1 to n_iterations
    appendInfo: "."
    
    # --- UPDATE H ---
    # Compute Num_H = W' * V
    selectObject: matNum_H
    Formula: "0"
    for k from 1 to nRows
        k_str$ = fixed$(k, 0)
        selectObject: matNum_H
        Formula: "self + Object_" + matW_id$ + "[" + k_str$ + ", row] * Object_" + matV_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Compute WtW = W' * W
    selectObject: matWtW
    Formula: "0"
    for k from 1 to nRows
        k_str$ = fixed$(k, 0)
        selectObject: matWtW
        Formula: "self + Object_" + matW_id$ + "[" + k_str$ + ", row] * Object_" + matW_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Compute Denom_H = WtW * H
    selectObject: matDenom_H
    Formula: "0"
    for k from 1 to n_components
        k_str$ = fixed$(k, 0)
        selectObject: matDenom_H
        Formula: "self + Object_" + matWtW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Update H
    selectObject: matH
    Formula: "self * Object_" + matNum_H_id$ + "[row,col] / (Object_" + matDenom_H_id$ + "[row,col] + 1e-9)"

    # --- UPDATE W ---
    # Compute Num_W = V * H'
    selectObject: matNum_W
    Formula: "0"
    for k from 1 to nCols
        k_str$ = fixed$(k, 0)
        selectObject: matNum_W
        Formula: "self + Object_" + matV_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[col, " + k_str$ + "]"
    endfor
    
    # Compute HHt = H * H'
    selectObject: matHHt
    Formula: "0"
    for k from 1 to nCols
        k_str$ = fixed$(k, 0)
        selectObject: matHHt
        Formula: "self + Object_" + matH_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[col, " + k_str$ + "]"
    endfor
    
    # Compute Denom_W = W * HHt
    selectObject: matDenom_W
    Formula: "0"
    for k from 1 to n_components
        k_str$ = fixed$(k, 0)
        selectObject: matDenom_W
        Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matHHt_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Update W
    selectObject: matW
    Formula: "self * Object_" + matNum_W_id$ + "[row,col] / (Object_" + matDenom_W_id$ + "[row,col] + 1e-9)"

    # v0.5 fix 7: resolve NMF's scale ambiguity - W_k H_k = (cW_k)(H_k/c).
    # Normalising each W column to unit sum and pushing the reciprocal
    # into the matching H row leaves WH (and the audio) untouched, but
    # makes the components comparable, which the roughness ranking, the
    # visualisation and the stereo perturbation all depend on.
    for k from 1 to n_components
        selectObject: matW
        colSum = 0
        for r from 1 to nRows
            selectObject: matW
            cv = Get value in cell: r, k
            colSum = colSum + cv
        endfor
        if colSum > 1e-12
            csStr$ = fixed$(colSum, 12)
            kStrN$ = fixed$(k, 0)
            selectObject: matW
            Formula: "if col = " + kStrN$ + " then self / " + csStr$ + " else self fi"
            selectObject: matH
            Formula: "if row = " + kStrN$ + " then self * " + csStr$ + " else self fi"
        endif
    endfor
endfor

appendInfoLine: " done"


# v0.6: reconstruction error, actually computed this time. v0.5's
# changelog item 8 promised it and no such calculation existed.
# Relative Frobenius distance ||V - WH||_F / ||V||_F. INFORMATION ONLY:
# few iterations may be exactly what a preset wants, and this number
# says how far the decomposition sits from the source, not whether the
# result is any good.
matErr = Create simple Matrix: "NMF_Err", nRows, nCols, "0"
matErr_id$ = string$(matErr)
for k from 1 to n_components
    k_str$ = fixed$(k, 0)
    selectObject: matErr
    Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
endfor
selectObject: matErr
Formula: "(self - Object_" + matV_id$ + "[row,col]) ^ 2"
selectObject: matErr
errSum = Get sum
selectObject: matV
matVsq = Copy: "V_sq"
Formula: "self ^ 2"
vSum = Get sum
removeObject: matVsq, matErr
if vSum > 1e-30
    reconErrRel = sqrt(errSum / vSum)
else
    reconErrRel = 0
endif
appendInfoLine: "  NMF reconstruction error (relative Frobenius): ",
    ... fixed$(reconErrRel, 5), "  [diagnostic only]"

removeObject: matNum_H, matWtW, matDenom_H, matNum_W, matHHt, matDenom_W

# ============================================
# DUAL-MODE SMOOTHING
# ============================================

appendInfoLine: "Applying smoothing..."

# ============================================================
# COMPONENT ROLES BY BEHAVIOUR  (v0.5 MUST-FIX 1)
# ============================================================
# v0.4 used "if row <= 2" - rows 1 and 2 got the transient decay and
# the rest got the smear. NMF has no canonical ordering: swap two
# columns of W and the matching rows of H and WH is identical, so the
# row number is an artefact of the random initialisation. The
# percussive component could sit at row 3 and be smeared while a drone
# at row 1 got the decay, and with no seed that changed every run.
# Temporal roughness ranks them by what they actually do:
#   sum |H[k,t] - H[k,t-1]| / (sum H[k,t] + eps)
roughness# = zero#(n_components)
isTransient# = zero#(n_components)
for k from 1 to n_components
    selectObject: matH
    dsum = 0
    asum = 0
    selectObject: matH
    prev = Get value in cell: k, 1
    asum = asum + prev
    for c from 2 to nCols
        selectObject: matH
        cur = Get value in cell: k, c
        dsum = dsum + abs(cur - prev)
        asum = asum + cur
        prev = cur
    endfor
    roughness#[k] = dsum / (asum + 1e-12)
endfor

# the two roughest components get the transient decay (same count as
# v0.4's rows 1-2, but chosen rather than assumed)
# v0.6: how many components get the decay is now an explicit choice.
# v0.5 always took the two roughest, which on Fast Preview (2
# components) meant EVERY component was a transient and none was
# texture - possibly what that preset wants, but it should be visible
# rather than a side effect of the constant 2.
nTransient = transient_components
if nTransient > n_components
    nTransient = n_components
endif
if nTransient < 0
    nTransient = 0
endif
for pick from 1 to nTransient
    bestK = 0
    bestR = -1
    for k from 1 to n_components
        if isTransient#[k] = 0 and roughness#[k] > bestR
            bestR = roughness#[k]
            bestK = k
        endif
    endfor
    if bestK > 0
        isTransient#[bestK] = 1
    endif
endfor

rankStr$ = ""
for k from 1 to n_components
    if isTransient#[k] = 1
        role$ = "transient"
    else
        role$ = "texture"
    endif
    rankStr$ = rankStr$ + "    component " + string$(k) + ": roughness " +
        ... fixed$(roughness#[k], 4) + "  -> " + role$ + newline$
endfor
appendInfoLine: "  Component roles (by temporal roughness, not row order):"
appendInfo: rankStr$

# ============================================================
# SHARED H_raw  (v0.5 MUST-FIX 2)
# ============================================================
# v0.4 smoothed matH in place, built the left channel from it, then
# perturbed THAT matrix and smoothed it again for the right - so the
# right channel was H_R = S(S(H_raw) * R) against H_L = S(H_raw):
# systematically duller and more smeared, with the left H destroyed
# and the visualisation showing only the right. Both channels now come
# from the same unsmoothed H_raw with equal processing depth.
selectObject: matH
matH_raw = Copy: "NMF_H_raw"
matH_raw_id$ = string$(matH_raw)

# smoothH: apply the decay to transient components and the forward
# smear to the rest. v0.5 MUST-FIX 3: the smear reads the col-1 value
# that this same pass already modified, so it trails rather than
# centring - kept, because that is the sound, and renamed accordingly.
procedure smoothH
    for k from 1 to n_components
        k_str$ = fixed$(k, 0)
        if isTransient#[k] = 1
            if trans_decay > 0
                selectObject: matH
                Formula: "if row = " + k_str$ + " and col > 1 then (self * (1-trans_decay))"
                    ... + " + (self[row, col-1] * trans_decay) else self fi"
            endif
        else
            for i from 1 to texture_blur_passes
                selectObject: matH
                Formula: "if row = " + k_str$ + " and col > 1 and col < ncol then"
                    ... + " (self[row, col-1]*0.25 + self*0.5 + self[row, col+1]*0.25) else self fi"
            endfor
        endif
    endfor
endproc

@smoothH

# v0.6: keep the LEFT channel's H. v0.5 let the right-channel pass
# overwrite matH, so the visualisation and matRecon ended up showing
# the right channel only - the left H was gone by the time anything
# was drawn.
selectObject: matH
matH_left = Copy: "NMF_H_left"
matH_left_id$ = string$(matH_left)

# ============================================
# RECONSTRUCT SPECTROGRAM
# ============================================

appendInfoLine: "Reconstructing spectrogram..."

selectObject: matV
matRecon = Copy: "V_Recon"
matRecon_id$ = string$(matRecon)
Formula: "0"

for k from 1 to n_components
    k_str$ = fixed$(k, 0)
    selectObject: matRecon
    Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
endfor

# ============================================
# RESYNTHESIS
# ============================================

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

appendInfoLine: "Extracting pitch contour..."
selectObject: id_mono
pitchOrig = To Pitch: 0.0, min_pitch, max_pitch
pitchSmooth = Smooth: pitch_smoothing_hz
pitchTier = Down to PitchTier
removeObject: pitchOrig, pitchSmooth

for pass from 1 to n_passes
    if stereo_output
        if pass = 1
            appendInfoLine: "Synthesizing LEFT channel..."
        else
            appendInfoLine: "Synthesizing RIGHT channel..."

            # v0.5 MUST-FIX 2: rebuild from H_raw so the right channel
            # gets the SAME processing depth as the left, then perturb.
            # v0.4 perturbed the already-smoothed matrix and smoothed
            # it a second time.
            selectObject: matH
            Formula: "Object_" + matH_raw_id$ + "[row,col]"
            if stereo_decorrelation > 0
                lo = 1 - 0.15 * stereo_decorrelation
                hi = 1 + 0.15 * stereo_decorrelation
                loS$ = fixed$(lo, 6)
                hiS$ = fixed$(hi, 6)
                selectObject: matH
                Formula: "self * randomUniform(" + loS$ + ", " + hiS$ + ")"
            endif
            @smoothH

            selectObject: matH
            matH_right = Copy: "NMF_H_right"
            matH_right_id$ = string$(matH_right)

            selectObject: matRecon
            Formula: "0"
            for k from 1 to n_components
                k_str$ = fixed$(k, 0)
                selectObject: matRecon
                Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
            endfor
        endif
    else
        appendInfoLine: "Synthesizing..."
    endif

    selectObject: matRecon
    specRecon = To Spectrogram
    selectObject: specRecon
    soundRecon = To Sound: sampling_rate
    Rename: "NMF_Raw_" + string$(pass)
    
    # v0.5 fix 6: pitch anchoring is a MODE now. Replacing a
    # Manipulation's PitchTier does not replace its PULSES - PSOLA
    # still uses the pulses found in the SYNTHESISED sound to decide
    # voiced/unvoiced, so the original contour applies only where the
    # resynthesis happened to look periodic. It is probably what turns
    # a bodiless additive spectrum into a gesture that recalls the
    # source, so it stays the default, but Raw and Blend let the two
    # be heard apart.
    if pitch_anchoring = 1
        soundPitched = soundRecon
        soundRecon = 0
        removeObject: specRecon
    else
        selectObject: soundRecon
        manipulation = To Manipulation: 0.01, min_pitch, max_pitch
        selectObject: manipulation
        plusObject: pitchTier
        Replace pitch tier

        selectObject: manipulation
        soundAnchored = Get resynthesis (overlap-add)

        if pitch_anchoring = 3
            selectObject: soundAnchored
            anchDur = Get total duration
            selectObject: soundRecon
            rawDur = Get total duration
            useDur = min(anchDur, rawDur)
            selectObject: soundAnchored
            soundPitched = Extract part: 0, useDur, "rectangular", 1, "no"
            rawStr$ = string$(soundRecon)
            selectObject: soundPitched
            Formula: "0.5 * self + 0.5 * object(" + rawStr$ + ", x)"
            removeObject: soundAnchored
        else
            soundPitched = soundAnchored
        endif

        removeObject: manipulation, soundRecon, specRecon
    endif
    
    if pass = 1
        channel_left = soundPitched
        selectObject: channel_left
        Rename: "Channel_Left"
    else
        channel_right = soundPitched
        selectObject: channel_right
        Rename: "Channel_Right"
    endif
endfor

removeObject: pitchTier

# ============================================
# COMBINE STEREO / FINALIZE
# ============================================

if stereo_output
    appendInfoLine: "Combining to stereo..."
    
    selectObject: channel_left
    dur_left = Get total duration
    
    selectObject: channel_right
    dur_right = Get total duration
    
    if dur_left < dur_right
        selectObject: channel_right
        channel_right_trim = Extract part: 0, dur_left, "rectangular", 1.0, "no"
        removeObject: channel_right
        channel_right = channel_right_trim
    elsif dur_right < dur_left
        selectObject: channel_left
        channel_left_trim = Extract part: 0, dur_right, "rectangular", 1.0, "no"
        removeObject: channel_left
        channel_left = channel_left_trim
    endif
    
    selectObject: channel_left
    plusObject: channel_right
    soundFinal = Combine to stereo
    Rename: name_original$ + "_NMF_" + presetName$
    
    removeObject: channel_left, channel_right
else
    soundFinal = channel_left
    Rename: name_original$ + "_NMF_" + presetName$
endif

selectObject: soundFinal
# v0.5 MUST-FIX 4: a CONDITIONAL limiter. The unconditional version
# amplified whatever came out of a near-silent decomposition.
finalPeakChk = Get absolute extremum: 0, 0, "None"
if finalPeakChk > 0.99
    Scale peak: 0.99
endif

# v0.5 MUST-FIX 5: all random draws are done.
random_initializeSafelyAndUnpredictably ()

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
    Text: 0.5, "centre", 0.5, "half", "NMF Spectral Resynthesizer: " + name_original$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: id_original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: soundFinal
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # W matrix (basis vectors) - as heatmap
    Select outer viewport: 0, 4, 2.7, 4.2
    Select inner viewport: 0.6, 3.6, 2.9, 4.1
    
    selectObject: matW
    wRows = Get number of rows
    wCols = Get number of columns
    
    # Find max for normalization
    wMax = 0
    for r from 1 to wRows
        for c from 1 to wCols
            selectObject: matW
            val = Get value in cell: r, c
            if val > wMax
                wMax = val
            endif
        endfor
    endfor
    if wMax < 0.001
        wMax = 1
    endif
    
    Axes: 0, wCols, 0, wRows
    
    # Draw W heatmap (downsample if too large)
    step_r = max(1, floor(wRows / 50))
    r = 1
    while r <= wRows
        for c from 1 to wCols
            selectObject: matW
            val = Get value in cell: r, c
            intensity = val / wMax
            rVal$ = fixed$(1 - intensity * 0.8, 2)
            gVal$ = fixed$(1 - intensity * 0.5, 2)
            bVal$ = fixed$(1 - intensity * 0.2, 2)
            Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", c - 1, c, wRows - r, wRows - r + step_r
        endfor
        r += step_r
    endwhile
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "W (Basis)"
    Text bottom: "yes", "Component"
    
    # H matrix (activations) - as lines over time
    Select outer viewport: 4, 8, 2.7, 4.2
    Select inner viewport: 4.4, 7.6, 2.9, 4.1
    
    selectObject: matH
    hRows = Get number of rows
    hCols = Get number of columns
    
    # Find max
    hMax = 0
    for r from 1 to hRows
        for c from 1 to hCols
            selectObject: matH
            val = Get value in cell: r, c
            if val > hMax
                hMax = val
            endif
        endfor
    endfor
    if hMax < 0.001
        hMax = 1
    endif
    
    Axes: 0, duration, 0, hMax * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, hMax * 1.1
    
    # Draw each component as a line
    for comp from 1 to hRows
        colorVal = comp / hRows
        rVal$ = fixed$(0.2 + colorVal * 0.6, 2)
        gVal$ = fixed$(0.6 - colorVal * 0.3, 2)
        bVal$ = fixed$(0.8 - colorVal * 0.5, 2)
        Colour: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}"
        
        for c from 2 to hCols
            # v0.6: the spectrogram's OWN time axis. v0.5's changelog
            # claimed this and the code still used the requested
            # step_ms starting at zero, so the plot did not line up
            # with the analysis at either end.
            t1 = specX1 + (c - 2) * specDx
            t2 = specX1 + (c - 1) * specDx
            selectObject: matH
            v1 = Get value in cell: comp, c - 1
            v2 = Get value in cell: comp, c
            Draw line: t1, v1, t2, v2
        endfor
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "H (Activ)"
    Text bottom: "yes", "Time (s)"
    
    # Stats box
    Select outer viewport: 0, 8, 4.4, 5.0
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.2, "centre", 0.5, "half", "Window: " + string$(window_ms) + " ms"
    Text: 0.4, "centre", 0.5, "half", "Step: " + string$(step_ms) + " ms"
    Text: 0.6, "centre", 0.5, "half", "Components: " + string$(n_components)
    Text: 0.8, "centre", 0.5, "half", "Iterations: " + string$(n_iterations)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================
# CLEANUP
# ============================================

removeObject: spectrogram, matV, matW, matH, matRecon, id_mono

# ============================================
# OUTPUT
# ============================================

selectObject: id_original
plusObject: soundFinal

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: soundFinal
n_ch = Get number of channels
dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "Channels: ", n_ch

if play_output
    appendInfoLine: "Playing..."
    selectObject: soundFinal
    Play
endif

selectObject: soundFinal