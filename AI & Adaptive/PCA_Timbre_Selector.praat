# ============================================================
# Praat AudioTools - PCA_Timbre_Selector.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PCA Timbre Selector - Analyzes timbre and selects segments
#   using direct feature selection for presets, with PCA
#   visualization for understanding the timbre space.
#
# Changelog v1.6:
#   - VISUALIZATION STANDARDIZATION ONLY; PCA analysis, direct feature
#     selection, chunk construction, joins and output rendering are unchanged.
#   - Adopted the Praat AudioTools 8-inch page/grid convention with explicit
#     inner viewports, suite-standard title/subtitle, typography, neutral
#     panel colours, summary strip, and full-page export viewport.
#   - Preserved all original visual information: source/output waveforms,
#     selection mask, three PCA projections, loadings, and selection score.
#   - Standardized PCA loading colours and draw-safe object names.
#
# Changelog v1.3:
#   - Fixed info banner (3 writeInfoLine -> 1 + appendInfoLine; the
#     title line was being erased)
#   - Standardize feature columns (z-score) before PCA so the timbre
#     space isn't dominated by the Hz-scale features
#   - Output preserves stereo (chunks extracted from the original,
#     not the mono analysis copy)
#   - Subtitle centered; distance-panel label reflects the mode
#
# Changelog v1.2:
#   - Restored PCA scatter plots and eigenvector loadings
#   - Kept direct feature selection (presets sound different)
#   - Combined best of v1.0 and v1.1
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form PCA Timbre Selector v1.6
    optionmenu Preset: 1
        option Custom (within-file PCA targeting)
        option Bright (high spectral centroid)
        option Dark (low spectral centroid)
        option Noisy (low HNR)
        option Tonal (high HNR)
        option High Pitch
        option Low Pitch
        option Loud (high intensity)
        option Quiet (low intensity)
    positive Analysis_window_ms 25
    positive Frame_step_seconds 0.01
    positive F0_min 75
    positive F0_max 600
    positive Selection_percentile 25
    real Target_pc1 0.0
    real Target_pc2 0.0
    real Target_pc3 0.0
    optionmenu Pca_whiten: 1
        option Raw PC coordinates
        option Whitened (equal weight per axis)
    optionmenu Join_mode: 2
        option Hard montage
        option Short crossfade
        option Hann phrase shaping
    optionmenu Output_level_mode: 2
        option Preserve source gain
        option Conditional limiter
        option Normalize peak to 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Analysis_window_ms is the SPECTRAL ANALYSIS window, renamed from
# Segment_ms: it never set the length of the extracted audio. Selected
# frames contribute their own cell, [t - step/2, t + step/2], and
# adjacent cells merge into chunks.
# Selection_percentile is now a true rank: k = ceil(valid frames x
# percentile / 100), and the run reports how many frames that was.
# Custom targeting is WITHIN-FILE - axis signs, scales and meanings
# change with the material, so (1, -0.5, 0) is not the same timbre in
# another file. (0, 0, 0) is well defined: the file's average timbre.
# Output_level_mode matters most for Loud/Quiet: v1.3 always normalised
# to 0.99, so Quiet selected the quietest regions and then raised them
# to near full scale.
#
# ON MISSING VALUES (unchanged, now stated): undefined pitch, intensity,
# centroid, spread and HNR enter the PCA as 0 Hz, -100 dB, 0 Hz, 0 Hz
# and -50 dB. After z-scoring those are not "missing" - they are
# extreme points, so PC1/PC2 often describe voiced-and-active versus
# unvoiced-and-silent. That makes this an ACOUSTIC-STATE space rather
# than a pure timbre space, which is useful for mixed material but
# worth knowing.
segment_ms = analysis_window_ms

# ============================================
# VALIDATION  (v1.4)
# ============================================
if analysis_window_ms <= 0
    exitScript: "Analysis_window_ms must be greater than 0."
endif
if frame_step_seconds <= 0
    exitScript: "Frame_step_seconds must be greater than 0."
endif
if f0_min <= 0
    exitScript: "F0_min must be greater than 0."
endif
if f0_max <= f0_min
    exitScript: "F0_max must be greater than F0_min."
endif
if selection_percentile <= 0 or selection_percentile > 100
    exitScript: "Selection_percentile must be greater than 0 and at most 100."
endif

# ===== PRESET CONFIGURATION =====
if preset = 1
    presetName$ = "Custom"
    selectionFeature$ = "PCA"
    selectionDirection = 0
elsif preset = 2
    presetName$ = "Bright"
    selectionFeature$ = "centroid"
    selectionDirection = 1
elsif preset = 3
    presetName$ = "Dark"
    selectionFeature$ = "centroid"
    selectionDirection = -1
elsif preset = 4
    presetName$ = "Noisy"
    selectionFeature$ = "hnr"
    selectionDirection = -1
elsif preset = 5
    presetName$ = "Tonal"
    selectionFeature$ = "hnr"
    selectionDirection = 1
elsif preset = 6
    presetName$ = "HighPitch"
    selectionFeature$ = "pitch"
    selectionDirection = 1
elsif preset = 7
    presetName$ = "LowPitch"
    selectionFeature$ = "pitch"
    selectionDirection = -1
elsif preset = 8
    presetName$ = "Loud"
    selectionFeature$ = "intensity"
    selectionDirection = 1
elsif preset = 9
    presetName$ = "Quiet"
    selectionFeature$ = "intensity"
    selectionDirection = -1
endif

# ===== 1. SETUP =====
writeInfoLine: "=============================================="
appendInfoLine: "  PCA TIMBRE SELECTOR v1.6"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", sndName$
appendInfoLine: "Preset: ", presetName$
if selectionFeature$ <> "PCA"
    appendInfoLine: "Mode: Direct feature selection"
    appendInfoLine: "Feature: ", selectionFeature$
    if selectionDirection = 1
        appendInfoLine: "Direction: HIGH values (top ", selection_percentile, "%)"
    else
        appendInfoLine: "Direction: LOW values (bottom ", selection_percentile, "%)"
    endif
else
    appendInfoLine: "Mode: PCA targeting"
    appendInfoLine: "Target: (", target_pc1, ", ", target_pc2, ", ", target_pc3, ")"
endif
appendInfoLine: ""

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels

selectObject: snd
Copy: "Analysis_Work"
workSnd = selected("Sound")

# v1.4: a silent input leaves most columns constant, so the PCA is
# rank-deficient, Quiet/Noisy happily select the silence, and the old
# unconditional Scale peak amplified whatever numerical residue came
# out.
selectObject: workSnd
srcPeakChk = Get absolute extremum: 0, 0, "None"
if srcPeakChk < 1e-5
    removeObject: workSnd
    exitScript: "The selected Sound is silent (or near-silent); there is no timbre to analyse."
endif

if nch > 1
    selectObject: workSnd
    Convert to mono
    monoSnd = selected("Sound")
    selectObject: workSnd
    Remove
    workSnd = monoSnd
    selectObject: workSnd
    Rename: "Analysis_Work"
endif

# ===== 2. FEATURE EXTRACTION =====
appendInfoLine: "STEP 1: Extracting features..."

selectObject: workSnd
To Pitch: frame_step_seconds, f0_min, f0_max
pit = selected("Pitch")

selectObject: workSnd
To Intensity: 75, frame_step_seconds, "yes"
inten = selected("Intensity")

selectObject: workSnd
To Spectrogram: segment_ms/1000, fs/2, frame_step_seconds, 20, "Gaussian"
specg = selected("Spectrogram")

selectObject: workSnd
To Harmonicity (ac): frame_step_seconds, f0_min, 0.1, 4.5
harmo = selected("Harmonicity")

selectObject: pit
nF = Get number of frames
t0 = Get start time
dt = Get time step

if nF < 10
    removeObject: pit, inten, specg, harmo, workSnd
    exitScript: "Sound too short for analysis."
endif

# Feature names
feature$[1] = "Pitch"
feature$[2] = "Intensity"
feature$[3] = "Centroid"
feature$[4] = "Spread"
feature$[5] = "HNR"

# Feature arrays
pitch_vals# = zero#(nF)
pitchValid# = zero#(nF)
hnrValid# = zero#(nF)
intensity_vals# = zero#(nF)
centroid_vals# = zero#(nF)
spread_vals# = zero#(nF)
hnr_vals# = zero#(nF)
time_vals# = zero#(nF)

# Create TableOfReal for PCA
Create TableOfReal: "raw_features", nF, 5
feat = selected("TableOfReal")

for c from 1 to 5
    Set column label (index): c, feature$[c]
endfor

# Extract all features
for i from 1 to nF
    # v1.4 CRITICAL 2: ONE time grid, taken from the Pitch object's own
    # frame centres. v1.3 used Get start time (the domain start, 0) and
    # built t0 + (i-1)*dt, then read Intensity and Harmonicity by FRAME
    # INDEX. Measured on a 2 s file at a 10 ms step:
    #   Pitch        197 frames, frame 1 centred at 0.020 s
    #   Intensity    192 frames, frame 1 centred at 0.045 s
    #   Harmonicity  198 frames, frame 1 centred at 0.015 s
    # So the counts differ (index 197 runs PAST Intensity's 192 frames)
    # and each row mixed three different instants up to 30 ms apart.
    # Intensity and HNR are now queried BY TIME at the pitch frame's
    # centre.
    selectObject: pit
    t = Get time from frame number: i
    time_vals#[i] = t

    # Pitch
    selectObject: pit
    v = Get value in frame: i, "Hertz"
    if v = undefined or v <= 0
        v = 0
        pitchValid#[i] = 0
    else
        pitchValid#[i] = 1
    endif
    pitch_vals#[i] = v
    selectObject: feat
    # v1.4: log-frequency pitch for the PCA and the ranking, so
    # 100->200 Hz and 200->400 Hz are the same distance. v1.3 used raw
    # Hz, where a 100 Hz step means an octave low down and under four
    # semitones higher up.
    if v > 0
        Set value: i, 1, 12 * log2(v / 55)
    else
        Set value: i, 1, 0
    endif

    # Intensity - BY TIME, not by frame index
    selectObject: inten
    v = Get value at time: t, "cubic"
    if v = undefined
        v = -100
    endif
    intensity_vals#[i] = v
    selectObject: feat
    Set value: i, 2, v

    # Centroid & Spread
    selectObject: specg
    To Spectrum (slice): t
    spec = selected("Spectrum")
    cent = Get centre of gravity: 2
    spread = Get standard deviation: 2
    Remove
    
    if cent = undefined
        cent = 0
    endif
    if spread = undefined
        spread = 0
    endif
    centroid_vals#[i] = cent
    spread_vals#[i] = spread
    selectObject: feat
    Set value: i, 3, cent
    Set value: i, 4, spread
    
    # HNR
    # v1.5: an explicit validity flag. v1.4 filled undefined with -50
    # and then the Noisy/Tonal branch accepted only hnr > -40, so a
    # genuinely measured -45 dB frame was discarded with the undefined
    # ones - the Noisy preset was excluding the noisiest material it
    # had.
    selectObject: harmo
    v = Get value at time: t, "cubic"
    if v = undefined
        v = -50
        hnrValid#[i] = 0
    else
        hnrValid#[i] = 1
    endif
    hnr_vals#[i] = v
    selectObject: feat
    Set value: i, 5, v
endfor

removeObject: pit, inten, specg, harmo

appendInfoLine: "  ", nF, " frames analyzed"

# ===== 3. PCA (for visualization) =====
appendInfoLine: ""
appendInfoLine: "STEP 2: Running PCA..."

# Standardize feature columns (z-score) so PCA weights the Hz-scale
# and dB-scale features comparably, not by raw variance.
for c from 1 to 5
    selectObject: feat
    colMean = Get column mean (index): c
    colSd = Get column stdev (index): c
    if colSd <= 0
        colSd = 1
    endif
    for r from 1 to nF
        selectObject: feat
        v = Get value: r, c
        Set value: r, c, (v - colMean) / colSd
    endfor
endfor

selectObject: feat
To PCA
pca = selected("PCA")
# v1.4: eigenvalues, for the optional whitened PCA distance. Raw PC
# coordinates keep each axis's own variance, so PC1 - usually the
# largest - dominates a Euclidean distance. That is often what you
# want (PC1 is the file's main axis of variation), but it is not an
# equal-weight distance, so it is now a choice.


# Store eigenvector loadings
for pc from 1 to 3
    for f from 1 to 5
        selectObject: pca
        loading[pc, f] = Get eigenvector element: pc, f
    endfor
endfor

# Variance explained
selectObject: pca
var1 = Get fraction variance accounted for: 1, 1
var2 = Get fraction variance accounted for: 2, 2
var3 = Get fraction variance accounted for: 3, 3

appendInfoLine: "  Variance explained: PC1=", fixed$(var1 * 100, 1), "%, PC2=", fixed$(var2 * 100, 1), "%, PC3=", fixed$(var3 * 100, 1), "%"

# Project to PC space
selectObject: feat
plusObject: pca
To Configuration: 3
scores = selected("Configuration")
To TableOfReal
scoresTbl = selected("TableOfReal")
removeObject: scores

# Store PCA scores
pc1_vals# = zero#(nF)
pc2_vals# = zero#(nF)
pc3_vals# = zero#(nF)

for i from 1 to nF
    selectObject: scoresTbl
    pc1_vals#[i] = Get value: i, 1
    pc2_vals#[i] = Get value: i, 2
    pc3_vals#[i] = Get value: i, 3
endfor

# ===== 4. COMPUTE FEATURE STATISTICS =====
appendInfoLine: ""
appendInfoLine: "STEP 3: Computing statistics..."

# Centroid stats
sumCent = 0
countCent = 0
for i from 1 to nF
    if centroid_vals#[i] > 0
        sumCent += centroid_vals#[i]
        countCent += 1
    endif
endfor
meanCent = if countCent > 0 then sumCent / countCent else 1000 fi

sumSqCent = 0
for i from 1 to nF
    if centroid_vals#[i] > 0
        sumSqCent += (centroid_vals#[i] - meanCent)^2
    endif
endfor
sdCent = if countCent > 1 then sqrt(sumSqCent / (countCent - 1)) else 1 fi

# HNR stats
# Use the explicit validity flag here too, so genuinely measured very-low
# HNR values participate in the statistics just as they do in selection.
sumHNR = 0
countHNR = 0
for i from 1 to nF
    if hnrValid#[i] = 1
        sumHNR += hnr_vals#[i]
        countHNR += 1
    endif
endfor
meanHNR = if countHNR > 0 then sumHNR / countHNR else 0 fi

sumSqHNR = 0
for i from 1 to nF
    if hnrValid#[i] = 1
        sumSqHNR += (hnr_vals#[i] - meanHNR)^2
    endif
endfor
sdHNR = if countHNR > 1 then sqrt(sumSqHNR / (countHNR - 1)) else 1 fi

# Pitch stats
sumPitch = 0
countPitch = 0
for i from 1 to nF
    if pitch_vals#[i] > 0
        sumPitch += pitch_vals#[i]
        countPitch += 1
    endif
endfor
meanPitch = if countPitch > 0 then sumPitch / countPitch else 200 fi

sumSqPitch = 0
for i from 1 to nF
    if pitch_vals#[i] > 0
        sumSqPitch += (pitch_vals#[i] - meanPitch)^2
    endif
endfor
sdPitch = if countPitch > 1 then sqrt(sumSqPitch / (countPitch - 1)) else 50 fi

# Pitch deviation for the visualization uses the same log-frequency
# representation as High/Low Pitch ranking.
sumLogPitch = 0
countLogPitch = 0
for i from 1 to nF
    if pitch_vals#[i] > 0
        logPitchHere = 12 * log2(pitch_vals#[i] / 55)
        sumLogPitch += logPitchHere
        countLogPitch += 1
    endif
endfor
meanLogPitch = if countLogPitch > 0 then sumLogPitch / countLogPitch else 0 fi

sumSqLogPitch = 0
for i from 1 to nF
    if pitch_vals#[i] > 0
        logPitchHere = 12 * log2(pitch_vals#[i] / 55)
        sumSqLogPitch += (logPitchHere - meanLogPitch)^2
    endif
endfor
sdLogPitch = if countLogPitch > 1 then sqrt(sumSqLogPitch / (countLogPitch - 1)) else 1 fi

# Intensity stats
sumInt = 0
countInt = 0
for i from 1 to nF
    if intensity_vals#[i] > -90
        sumInt += intensity_vals#[i]
        countInt += 1
    endif
endfor
meanInt = if countInt > 0 then sumInt / countInt else 60 fi

sumSqInt = 0
for i from 1 to nF
    if intensity_vals#[i] > -90
        sumSqInt += (intensity_vals#[i] - meanInt)^2
    endif
endfor
sdInt = if countInt > 1 then sqrt(sumSqInt / (countInt - 1)) else 10 fi

appendInfoLine: "  Centroid: ", fixed$(meanCent, 0), " ± ", fixed$(sdCent, 0), " Hz"
appendInfoLine: "  HNR: ", fixed$(meanHNR, 1), " ± ", fixed$(sdHNR, 1), " dB"
appendInfoLine: "  Pitch: ", fixed$(meanPitch, 0), " ± ", fixed$(sdPitch, 0), " Hz"
appendInfoLine: "  Intensity: ", fixed$(meanInt, 1), " ± ", fixed$(sdInt, 1), " dB"

# v1.5: whitening scales are the PC scores' own standard deviations.
# v1.4 tried Get eigenvalue on the PCA object under nocheck; that query
# returns nothing in this build, so all three silently defaulted to 1
# and "Whitened" was identical to "Raw" - verified: both modes selected
# exactly the same 75 frames. Dividing each axis by its own spread is
# the same whitening and needs no query that may not exist.
procedure sdOf: .n
    .sum = 0
    for .i from 1 to .n
        .sum = .sum + sdSrc#[.i]
    endfor
    .mu = .sum / .n
    .ss = 0
    for .i from 1 to .n
        .d = sdSrc#[.i] - .mu
        .ss = .ss + .d * .d
    endfor
    if .n > 1
        sdOf.out = sqrt(.ss / (.n - 1))
    else
        sdOf.out = 1
    endif
    if sdOf.out < 1e-9
        sdOf.out = 1
    endif
endproc

sdSrc# = pc1_vals#
@sdOf: nF
eig1 = sdOf.out ^ 2
sdSrc# = pc2_vals#
@sdOf: nF
eig2 = sdOf.out ^ 2
sdSrc# = pc3_vals#
@sdOf: nF
eig3 = sdOf.out ^ 2

# ===== 5. SELECTION =====
appendInfoLine: ""
appendInfoLine: "STEP 4: Selecting frames..."

selected_mask# = zero#(nF)
dist_vals# = zero#(nF)

# ============================================================
# SELECTION BY RANK  (v1.4 CRITICAL 1)
# ============================================================
# v1.3 mapped the percentile to a fixed z threshold (25% -> 0.67 and so
# on), which assumes a clean Gaussian. Acoustic features almost never
# are: HNR separates voiced from unvoiced, intensity is skewed, pitch
# and centroid are often multi-modal. So "Selection_percentile = 20"
# could return 3%, 35%, or nothing at all. Custom mode was worse - its
# threshold was meanDist * (percentile / 50), which is neither a
# percentile nor a quantile of the distances.
#
# Ranking the valid frames and taking exactly k of them makes the
# number mean what the dialog says, and it removes the zero-standard-
# deviation division at the same time: if every value is identical
# there is no "top", and the run says so instead of dividing by 0.

nValidSel = 0
selVal# = zero#(nF)
selIdx# = zero#(nF)

if selectionFeature$ = "centroid"
    for i from 1 to nF
        if centroid_vals#[i] > 0
            nValidSel += 1
            selVal#[nValidSel] = centroid_vals#[i]
            selIdx#[nValidSel] = i
            dist_vals#[i] = abs(centroid_vals#[i] - meanCent) / max(sdCent, 1e-9)
        endif
    endfor
elsif selectionFeature$ = "hnr"
    for i from 1 to nF
        # v1.5: use the VALIDITY flag, not a -40 dB cut. v1.4 rejected
        # any frame below -40, so a genuinely measured HNR of -45 dB was
        # discarded alongside the undefined ones - and the Noisy preset
        # was therefore excluding the noisiest material it could find.
        if hnrValid#[i] = 1
            nValidSel += 1
            selVal#[nValidSel] = hnr_vals#[i]
            selIdx#[nValidSel] = i
            dist_vals#[i] = abs(hnr_vals#[i] - meanHNR) / max(sdHNR, 1e-9)
        endif
    endfor
elsif selectionFeature$ = "pitch"
    for i from 1 to nF
        if pitch_vals#[i] > 0
            nValidSel += 1
            # v1.4: rank on log frequency, so the percentile follows
            # musical intervals rather than Hz differences.
            selVal#[nValidSel] = 12 * log2(pitch_vals#[i] / 55)
            selIdx#[nValidSel] = i
            logPitchHere = 12 * log2(pitch_vals#[i] / 55)
            dist_vals#[i] = abs(logPitchHere - meanLogPitch) / max(sdLogPitch, 1e-9)
        endif
    endfor
elsif selectionFeature$ = "intensity"
    for i from 1 to nF
        if intensity_vals#[i] > -90
            nValidSel += 1
            selVal#[nValidSel] = intensity_vals#[i]
            selIdx#[nValidSel] = i
            dist_vals#[i] = abs(intensity_vals#[i] - meanInt) / max(sdInt, 1e-9)
        endif
    endfor
else
    # Custom PCA: rank by DISTANCE to the target, smallest first.
    # NOTE: the target is only meaningful inside THIS file's PCA space -
    # axis signs, scales and meanings all change with the material, so
    # (1, -0.5, 0) is not the same timbre in another file. (0, 0, 0) is
    # well defined: the file's average timbre.
    t1 = target_pc1
    t2 = target_pc2
    t3 = target_pc3
    for i from 1 to nF
        # v1.5: option 1 is "Raw PC coordinates", option 2 is
        # "Whitened". v1.4 tested = 1 and so did the opposite of the
        # dialog in both positions.
        if pca_whiten = 2
            e1 = max(sqrt(eig1), 1e-9)
            e2 = max(sqrt(eig2), 1e-9)
            e3 = max(sqrt(eig3), 1e-9)
            d = sqrt(((pc1_vals#[i] - t1)/e1)^2 + ((pc2_vals#[i] - t2)/e2)^2
                ... + ((pc3_vals#[i] - t3)/e3)^2)
        else
            d = sqrt((pc1_vals#[i] - t1)^2 + (pc2_vals#[i] - t2)^2 + (pc3_vals#[i] - t3)^2)
        endif
        dist_vals#[i] = d
        nValidSel += 1
        # v1.5: store the DISTANCE, not its negation. v1.4 stored -d and
        # Custom uses selectionDirection = 0, which takes the LOWEST
        # values - and the lowest -d is the LARGEST distance. Custom
        # targeting was selecting the frames FURTHEST from the target:
        # distances 0.2, 0.8, 2.0 became -0.2, -0.8, -2.0 and -2.0 was
        # picked first. It implemented PCA avoidance.
        selVal#[nValidSel] = d
        selIdx#[nValidSel] = i
    endfor
endif

if nValidSel < 1
    removeObject: workSnd
    exitScript: "No frame has a usable value for this preset's feature."
endif

# how many to take
kTake = ceiling(nValidSel * selection_percentile / 100)
if kTake < 1
    kTake = 1
endif
if kTake > nValidSel
    kTake = nValidSel
endif

# is the feature actually varying?
minSel = selVal#[1]
maxSel = selVal#[1]
for v from 2 to nValidSel
    if selVal#[v] < minSel
        minSel = selVal#[v]
    endif
    if selVal#[v] > maxSel
        maxSel = selVal#[v]
    endif
endfor
if maxSel - minSel < 1e-12
    appendInfoLine: "  ! This feature does not vary across the file - there is no"
    appendInfoLine: "    'top' or 'bottom' to select. Taking the first ", kTake,
        ... " valid frames in time order."
    for v from 1 to kTake
        idxHere = selIdx#[v]
        selected_mask#[idxHere] = 1
    endfor
else
    # partial selection sort: pull the kTake extreme values to the front
    for a from 1 to kTake
        bestPos = a
        for b from a + 1 to nValidSel
            if selectionDirection = 1
                if selVal#[b] > selVal#[bestPos]
                    bestPos = b
                endif
            else
                if selVal#[b] < selVal#[bestPos]
                    bestPos = b
                endif
            endif
        endfor
        tmpV = selVal#[a]
        selVal#[a] = selVal#[bestPos]
        selVal#[bestPos] = tmpV
        tmpI = selIdx#[a]
        selIdx#[a] = selIdx#[bestPos]
        selIdx#[bestPos] = tmpI
        idxHere = selIdx#[a]
        selected_mask#[idxHere] = 1
    endfor
endif

appendInfoLine: "  Requested ", fixed$(selection_percentile, 1), "% of ",
    ... nValidSel, " valid frames -> ", kTake, " frames selected"

# Count selected
selected_frame_count = 0
for i from 1 to nF
    if selected_mask#[i] = 1
        selected_frame_count += 1
    endif
endfor

appendInfoLine: "  Selected: ", selected_frame_count, " of ", nF, " frames (", fixed$(100 * selected_frame_count / nF, 1), "%)"

# ===== 6. BUILD OUTPUT =====
appendInfoLine: ""
appendInfoLine: "STEP 5: Building output..."

if selected_frame_count < 2
    removeObject: feat, pca, scoresTbl, workSnd
    exitScript: "Too few frames selected. Try increasing Selection percentile."
endif

chunk_count = 0
minChunkDur = 1e9
chunk_start = -1
chunk_end = -1

for i from 1 to nF
    # v1.4 CRITICAL 2: the frame's cell is CENTRED on its own time.
    # v1.3 took [t, t+dt], so the audio began where the feature was
    # measured and ran forward past it.
    t_s = time_vals#[i] - dt/2
    t_e = time_vals#[i] + dt/2
    if t_s < 0
        t_s = 0
    endif
    if t_e > dur
        t_e = dur
    endif
    
    if selected_mask#[i] = 1
        if chunk_start = -1
            chunk_start = t_s
        endif
        chunk_end = t_e
    else
        if chunk_start <> -1
            selectObject: snd
            if join_mode = 3
                Extract part: chunk_start, chunk_end, "Hanning", 1, "no"
            else
                Extract part: chunk_start, chunk_end, "rectangular", 1, "no"
            endif
            chunkID = selected("Sound")
            selectObject: chunkID
            thisChunkDur = Get total duration
            if chunk_count = 0 or thisChunkDur < minChunkDur
                minChunkDur = thisChunkDur
            endif
            chunk_count += 1
            chunk_id_'chunk_count' = chunkID
            chunk_start = -1
        endif
    endif
endfor

if chunk_start <> -1
    selectObject: snd
    # v1.5: the trailing chunk follows Join_mode too. v1.4 hard-coded
    # Hanning here, so in Hard montage or Short crossfade every chunk
    # was rectangular except the last, which got a full Hann - an
    # unexplained fade at the end of the piece.
    if join_mode = 3
        Extract part: chunk_start, chunk_end, "Hanning", 1, "no"
    else
        Extract part: chunk_start, chunk_end, "rectangular", 1, "no"
    endif
    chunkID = selected("Sound")
    # v1.5: the trailing chunk counts toward minChunkDur too. v1.4
    # updated it only inside the loop, so if the LAST chunk was the
    # shortest the crossfade could exceed 30% of it - most likely
    # exactly when the selection ends on a single frame.
    selectObject: chunkID
    thisChunkDur = Get total duration
    if chunk_count = 0 or thisChunkDur < minChunkDur
        minChunkDur = thisChunkDur
    endif
    chunk_count += 1
    chunk_id_'chunk_count' = chunkID
endif

appendInfoLine: "  Segments: ", chunk_count

if chunk_count > 0
    selectObject: chunk_id_1
    for i from 2 to chunk_count
        plusObject: chunk_id_'i'
    endfor
    
    # v1.4 CRITICAL 4: v1.3 applied a full Hann to EVERY chunk and then
    # crossfaded on top. On a 20-40 ms chunk the Hann attenuates most of
    # it, so the result carried a dynamic arch per chunk plus a dip at
    # every join - a real effect, but not "neutral timbre selection".
    # Join_mode makes it a choice; the crossfade is bounded by the
    # shortest chunk so it cannot swallow one whole.
    if join_mode = 1
        Concatenate
    else
        xfUse = 0.01
        if xfUse > minChunkDur * 0.3
            xfUse = minChunkDur * 0.3
        endif
        if xfUse < 0.0005
            Concatenate
        else
            Concatenate with overlap: xfUse
        endif
    endif
    Rename: sndName$ + "_" + presetName$
    finalSnd = selected("Sound")
    # v1.4 CRITICAL 5: normalising every result to 0.99 contradicts the
    # Quiet preset outright - it picks the quietest regions of the
    # source and then raises them to near full scale, erasing the level
    # difference between Loud and Quiet entirely.
    outPeakNow = Get absolute extremum: 0, 0, "None"
    if output_level_mode = 3
        Scale peak: 0.99
    elsif output_level_mode = 2 and outPeakNow > 0.99
        Scale peak: 0.99
    endif
    
    selectObject: finalSnd
    finalDur = Get total duration
    
    for i from 1 to chunk_count
        removeObject: chunk_id_'i'
    endfor
    
    appendInfoLine: "  Output: ", fixed$(finalDur, 2), " s (", fixed$(100 * finalDur / dur, 1), "%)"
else
    removeObject: feat, pca, scoresTbl, workSnd
    exitScript: "No segments created."
endif

# ===== 7. VISUALIZATION =====
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "STEP 6: Visualization..."

    pageHeight = 8.45
    Erase all
    Select outer viewport: 0, 8, 0, pageHeight

    # Draw-safe source name
    vizSndName$ = replace$(sndName$, "_", "\_ ", 0)

    if pca_whiten = 2
        whitenDesc$ = "whitened PCA"
    else
        whitenDesc$ = "raw PCA"
    endif

    if join_mode = 1
        joinDesc$ = "hard montage"
    elsif join_mode = 2
        joinDesc$ = "short crossfade"
    else
        joinDesc$ = "Hann phrase shaping"
    endif

    if output_level_mode = 1
        levelDesc$ = "preserve source gain"
    elsif output_level_mode = 2
        levelDesc$ = "conditional limiter"
    else
        levelDesc$ = "normalize peak to 0.99"
    endif

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PCA Timbre Selector v1.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizSndName$ + " | " + presetName$ + " | " + fixed$(100 * selected_frame_count / nF, 1) + "\% selected | " + string$(chunk_count) + " segments"

    # === Source waveform ===
    Select outer viewport: 0, 8, 0.66, 1.52
    Select inner viewport: 0.60, 7.70, 0.78, 1.36
    selectObject: snd
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text top: "no", "Original Sound"

    # === Selected output waveform ===
    Select outer viewport: 0, 8, 1.66, 2.52
    Select inner viewport: 0.60, 7.70, 1.78, 2.36
    selectObject: finalSnd
    Colour: "{0.25, 0.55, 0.35}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "no", "Time (s)"
    Text top: "no", presetName$ + " selection | " + fixed$(finalDur, 2) + " s"

    # === Selection timeline ===
    Select outer viewport: 0, 8, 2.68, 3.28
    Select inner viewport: 0.60, 7.70, 2.78, 3.14
    Axes: 0, dur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, 0, 1

    for i from 1 to nF
        t_s = time_vals#[i] - dt/2
        t_e = time_vals#[i] + dt/2
        if selected_mask#[i] = 1
            Paint rectangle: "{0.30, 0.70, 0.40}", t_s, t_e, 0, 1
        else
            Paint rectangle: "{0.86, 0.86, 0.86}", t_s, t_e, 0, 1
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mask"
    Text top: "no", "Frame Selection Timeline | green = selected | grey = rejected"

    # === PCA scatter plots ===
    minPC1 = min(pc1_vals#)
    maxPC1 = max(pc1_vals#)
    minPC2 = min(pc2_vals#)
    maxPC2 = max(pc2_vals#)
    minPC3 = min(pc3_vals#)
    maxPC3 = max(pc3_vals#)

    pc1Range = max(maxPC1 - minPC1, 0.1)
    pc2Range = max(maxPC2 - minPC2, 0.1)
    pc3Range = max(maxPC3 - minPC3, 0.1)

    # PC1 vs PC2
    Select outer viewport: 0, 2.75, 3.48, 5.32
    Select inner viewport: 0.60, 2.55, 3.68, 5.08
    Axes: minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.97}", minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1

    for i from 1 to nF
        if selected_mask#[i] = 1
            Paint circle: "{0.30, 0.70, 0.40}", pc1_vals#[i], pc2_vals#[i], pc1Range * 0.015
        else
            Paint circle: "{0.80, 0.80, 0.80}", pc1_vals#[i], pc2_vals#[i], pc1Range * 0.012
        endif
    endfor
    if selectionFeature$ = "PCA"
        Paint circle: "{0.90, 0.20, 0.20}", t1, t2, pc1Range * 0.04
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "PC2"
    Text bottom: "no", "PC1"
    Font size: 7
    Text top: "no", "PC1 vs PC2"

    # PC1 vs PC3
    Select outer viewport: 2.75, 5.25, 3.48, 5.32
    Select inner viewport: 3.00, 5.05, 3.68, 5.08
    Axes: minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.97}", minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1

    for i from 1 to nF
        if selected_mask#[i] = 1
            Paint circle: "{0.30, 0.70, 0.40}", pc1_vals#[i], pc3_vals#[i], pc1Range * 0.015
        else
            Paint circle: "{0.80, 0.80, 0.80}", pc1_vals#[i], pc3_vals#[i], pc1Range * 0.012
        endif
    endfor
    if selectionFeature$ = "PCA"
        Paint circle: "{0.90, 0.20, 0.20}", t1, t3, pc1Range * 0.04
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "PC3"
    Text bottom: "no", "PC1"
    Font size: 7
    Text top: "no", "PC1 vs PC3"

    # PC2 vs PC3
    Select outer viewport: 5.25, 8, 3.48, 5.32
    Select inner viewport: 5.50, 7.70, 3.68, 5.08
    Axes: minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.97}", minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1

    for i from 1 to nF
        if selected_mask#[i] = 1
            Paint circle: "{0.30, 0.70, 0.40}", pc2_vals#[i], pc3_vals#[i], pc2Range * 0.015
        else
            Paint circle: "{0.80, 0.80, 0.80}", pc2_vals#[i], pc3_vals#[i], pc2Range * 0.012
        endif
    endfor
    if selectionFeature$ = "PCA"
        Paint circle: "{0.90, 0.20, 0.20}", t2, t3, pc2Range * 0.04
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "PC3"
    Text bottom: "no", "PC2"
    Font size: 7
    Text top: "no", "PC2 vs PC3"

    # === Compact scatter legend ===
    Select outer viewport: 0, 8, 5.34, 5.64
    Select inner viewport: 0.60, 7.70, 5.36, 5.62
    Axes: 0, 1, 0, 1
    Font size: 6
    Paint circle: "{0.30, 0.70, 0.40}", 0.12, 0.5, 0.012
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.14, "left", 0.5, "half", "Selected"
    Paint circle: "{0.80, 0.80, 0.80}", 0.31, 0.5, 0.010
    Text: 0.33, "left", 0.5, "half", "Rejected"
    if selectionFeature$ = "PCA"
        Paint circle: "{0.90, 0.20, 0.20}", 0.50, 0.5, 0.015
        Text: 0.52, "left", 0.5, "half", "Target"
    endif
    Text: 0.98, "right", 0.5, "half", "Variance PC1/2/3 = " + fixed$(var1 * 100, 1) + "/" + fixed$(var2 * 100, 1) + "/" + fixed$(var3 * 100, 1) + "\% "

    # === Eigenvector loadings ===
    Select outer viewport: 0, 4, 5.80, 7.18
    Select inner viewport: 0.60, 3.85, 6.00, 6.96
    Axes: 0, 6, -1, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 6, -1, 1

    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, 6, 0

    barWidth = 0.25
    colours$[1] = "{0.75, 0.25, 0.25}"
    colours$[2] = "{0.25, 0.55, 0.25}"
    colours$[3] = "{0.25, 0.35, 0.75}"

    for f from 1 to 5
        baseX = f - 0.3
        for pc from 1 to 3
            x1 = baseX + (pc - 1) * barWidth
            x2 = x1 + barWidth * 0.8
            val = loading[pc, f]
            Paint rectangle: colours$[pc], x1, x2, 0, val
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    for f from 1 to 5
        Text: f, "centre", -1.10, "top", feature$[f]
    endfor
    Text left: "yes", "Loading"
    Font size: 7
    Text top: "no", "PCA Loadings | PC1 red | PC2 green | PC3 blue"

    # === Selection distance / feature deviation over time ===
    Select outer viewport: 4, 8, 5.80, 7.18
    Select inner viewport: 4.45, 7.70, 6.00, 6.96

    maxDist = max(dist_vals#)
    if maxDist < 0.1
        maxDist = 1
    endif

    Axes: 0, dur, 0, maxDist * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, 0, maxDist * 1.1

    Colour: "{0.25, 0.45, 0.75}"
    for i from 2 to nF
        Draw line: time_vals#[i-1], dist_vals#[i-1], time_vals#[i], dist_vals#[i]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    if selectionFeature$ = "PCA"
        Text left: "yes", "Distance"
        scoreTitle$ = "Distance to PCA target"
    else
        Text left: "yes", "|standardized deviation|"
        scoreTitle$ = "Feature deviation from mean"
    endif
    Text bottom: "no", "Time (s)"
    Font size: 7
    Text top: "no", scoreTitle$ + " | " + selectionFeature$

    # === Summary strip ===
    Select outer viewport: 0, 8, 7.42, 8.38
    Select inner viewport: 0.60, 7.70, 7.50, 8.30
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizSndName$ + " | " + fixed$(dur, 2) + " s | " + string$(nF) + " frames | analysis window " + fixed$(analysis_window_ms, 0) + " ms"
    summary2$ = "##Selection##  " + presetName$ + " | " + fixed$(selection_percentile, 1) + "\% requested | " + string$(selected_frame_count) + " frames selected | " + string$(chunk_count) + " segments | " + whitenDesc$
    summary3$ = "##Output##  " + fixed$(finalDur, 2) + " s (" + fixed$(100 * finalDur / dur, 1) + "\% of source) | " + joinDesc$ + " | " + levelDesc$
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

# ===== CLEANUP =====
removeObject: feat, pca, scoresTbl, workSnd

# ===== OUTPUT =====
selectObject: snd
plusObject: finalSnd

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="

if play_result
    selectObject: finalSnd
    Play
endif

selectObject: finalSnd
