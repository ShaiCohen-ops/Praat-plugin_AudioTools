# ============================================================
# Praat AudioTools - Self-Similarity_Spectral_Resynthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.4.1 (2026)
#
# Changelog v3.4.1 (2026):
#   - FORM: compact main page now contains only Preset, Creative mode, Spatial
#     mode, Edit details, Visualization, and Play. Analysis/SSM/gain/output
#     engineering controls moved to an optional Details pause window.
#   - UX: Custom defaults are initialized explicitly before preset loading;
#     named preset values are applied BEFORE Edit details opens, so the Details
#     window always shows the values that will actually render.
#   - AUDIO: no DSP or preset calibration changes from v3.4.
# Changelog v3.4 (2026):
#   - PRESETS/MUSICAL BALANCE: recalibrated the six named presets as one
#     progression. Gentle stays subtle; Ghost is moderate; Glitch/Brutal retain
#     clear gating/novelty character without the old -36/-48 dB near-mutes;
#     Chaotic Tremolo now uses the intended 3-level quantizer instead of a hard
#     gate that collapsed it to two levels. Spectral Mosaic is unchanged.
#   - ADAPTIVE SCORE SCALING: gain mapping now centers the score by its mean and
#     standard deviation, then uses a bounded logistic map. v3.3 min-max scaling
#     let a few outlier frames pin almost the whole file near one extreme, making
#     some presets nearly inert and others destructive on different sources.
#   - FIX/SEMANTICS: Add_chaos (0..1) is now applied in normalized similarity
#     units, so the same preset depth means the same thing across source files.
#   - ROBUSTNESS: a nearly flat similarity curve maps to neutral 0.5 rather than
#     dividing by an arbitrary tiny range; chaos presets can still animate it.
#   - QC: Info reports score spread and the pre-envelope dB gain range so an
#     unexpectedly flat or aggressive response is visible without guessing.
# Changelog v3.3 (2026):
#   - FIX: stereo/multichannel analysis no longer uses Convert to mono, which
#     could cancel anti-phase material before MFCC extraction. The strongest-RMS
#     source channel now drives the similarity analysis.
#   - FIX/QUALITY: Self-Mosaic now copies blocks from the full-rate ORIGINAL
#     source with its channel layout preserved (Mono spatial mode remains mono).
#     This fixes silent anti-phase mosaics and prevents unnecessary stereo loss.
#   - MEMORY: Stage 4 no longer allocates two extra frames x frames threshold/count
#     matrices. Scores are accumulated row-by-row from the existing SSM, reducing
#     peak memory substantially while preserving the same score law.
#   - FIX: Hard Quantized now really has three levels (0, 0.5, 1) rather than
#     floor(x*3)/3, which could produce four levels.
#   - CLARITY: Speed mode renamed Analysis bandwidth; lowering analysis SR changes
#     MFCC bandwidth and is not guaranteed to be faster because the SSM cost is
#     driven mainly by frame count. Full-rate audio output is preserved.
#   - ROBUSTNESS: parameter validation, explicit short-source diagnostic, safe
#     post-gain peak cap, and zero-valued threshold/mask smoothing are legal.
#   - VIZ: removed the misleading similarity-threshold line from the SCORE panel;
#     that threshold applies to raw SSM cells before averaging, not to score values.
# Changelog v3.2.1 (2026):
#   - UX: every named preset overrides the Creative_mode menu as
#     part of its recipe (SpectralMosaic IS mosaic mode, etc.) --
#     previously with no indication anywhere. The form now says
#     so under the menu, and the info window prints a NOTE when
#     the menu selection was overridden. For hybrid combinations
#     (e.g. GhostRemix parameters with Inverted mode), use the
#     Custom preset -- all fields are exposed.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Similarity-driven amplitude modulator. Despite the script name,
#   this is NOT spectral resynthesis in the strict sense — the audio
#   is never decomposed and reconstructed in the spectral domain.
#   Instead: MFCC features drive a time-varying gain envelope that
#   is applied to the original waveform. The result is shaped by
#   self-similarity but spectrally faithful to the source.
#
#   With gentle settings: subtle dynamic emphasis of recurring
#   spectral material. With aggressive settings: tremolo, gating,
#   glitch textures.
#
#   The Self-Mosaic mode is the one exception: it splices audio
#   blocks from the source's most-similar frames, which is closer
#   to true content-driven resynthesis (with frame-boundary clicks
#   inherent to the technique).
#
# Algorithm:
#   1. Extract MFCC frames from input
#   2. L2-normalize each frame's coefficient vector
#   3. SSM[i,j] = cosine similarity of frame i and frame j
#                = sum over coefficients c of (N[c,i] * N[c,j])
#   4. Per-frame score = mean of cells > threshold (or variant
#      per creative_mode)
#   5. Optional smoothing of score curve
#   6. Center/scale score -> contrast curve -> dB gain
#   7. Apply gain as time-varying envelope to the source
#
# Changelog v3.2 (2026):
#   - FIX (audible): Self-Mosaic copied its blocks from the
#     ANALYSIS copy, which on the default Balanced speed mode is
#     16 kHz -- the mosaic output, after upsampling, contained
#     nothing above 8 kHz (the recurring "muffled" pattern, here
#     hiding in one mode). Blocks now copy from the full-rate
#     mono source; the upsample step is gone. The envelope modes
#     always did this correctly (cheap analysis, full-rate
#     output) and are unchanged.
#   - FIX: the mosaic loop stopped at actual_frames - 1, leaving
#     the final block silent.
#   - FIX: the info header still announced v3.0.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only form is the margin-compression collision
#     geometry).
#   - AUDIT: verified correct as written -- the vectorized SSM
#     accumulation (frozen reads), the score smoother, the
#     dB-domain envelope interpolation (clamp algebra collapses
#     to constant extrapolation at both edges), the True M/S
#     encode/decode, and the envelope unity path (measured: boost
#     0 / atten 0 reconstructs the input; see tests).
#
# Changelog v3.1:
#   - Defaults rebalanced toward gentle / musical. Form defaults
#     were "moderately aggressive" in v3.0 (boost 12 dB, atten
#     -24 dB, contrast 4, env smoothing 5 ms), which produced
#     pumping and steppy artifacts on most material. v3.1
#     defaults: boost 4 dB, atten -8 dB, contrast 2, env smoothing
#     50 ms, mask smoothing 8 frames, no chaos. Subtle by default;
#     opt in to brutal via the named presets.
#   - New preset "Gentle Resynthesis" added as slot 2 (now the
#     default selection). Embodies the description's "subtle
#     spectral enhancement" claim. All other preset numbers
#     shifted up by one.
#   - Envelope sample rate raised from 100 Hz to 1000 Hz. The
#     old rate meant any envelope_smoothing_ms below ~10 ms
#     rounded to 0 taps and was silently skipped. At 1000 Hz,
#     1 ms = 1 tap of moving-average smoothing.
#   - Header description rewritten to honestly describe what
#     the script does (similarity-driven amplitude modulation),
#     not what its name implies (spectral resynthesis). Script
#     filename unchanged for repository-link continuity.
# Changelog v3.0:
#   - Fix (CORRECTNESS, headline): preset matching was broken.
#     v2.2 used `if preset$ = "Glitch Gating"` but `preset$`
#     never existed — Praat's optionMenu creates a numeric
#     variable (preset), not a string. Every preset run fell
#     through to Custom and used whatever happened to be in
#     the form fields. v3.0 uses numeric matching. Same bug
#     also hit creative_mode$ and spatial_mode$ in the Info
#     output and visualization title — now uses computed
#     name strings.
#   - Fix (CORRECTNESS): SSM stride mismatch. v2.2 computed
#     SSM at row+=5, col+=5 (so 96% of cells were 0), then
#     scoring stepped col+=10 (sampling 10% of frames), but
#     gain mapping consumed every frame's score. Result:
#     long stretches of low-similarity_attenuation alternating
#     with sparse computed values — a "glitch" character that
#     was being mistaken for the intended effect. v3.0
#     computes the full SSM (vectorized, fast) and scores
#     every frame.
#   - Speed (HEADLINE): all four hot loops vectorized.
#       Stage 2 (normalize): one row-by-row Get/Set replaced
#         by per-row Get sum + scalar Formula (sum is C++).
#       Stage 3 (SSM): O(coeffs) Formula passes accumulating
#         outer products into SSM, instead of O(frames^2 * coeffs)
#         individual Get value calls. For 1000 frames, 8 coeffs:
#         drops from ~6M Gets to 8 Formula passes. Realistic
#         50-100x speedup on Stage 3.
#       Stage 4 (scoring): row sum via Formula + Get sum
#         instead of per-cell loop.
#       Stage 7 (mosaic): per-frame block copy via Formula (part)
#         with cross-Sound reference, replacing per-sample
#         Get/Set value at sample number.
#   - Fix (TRUTH-IN-LABELING): spatial mode names corrected.
#       v2.2 "Mid-Side (process center only)" was actually just
#         AM with a DC offset (0.5 + 0.5*env), no mid/side
#         decomposition at all. Renamed to
#         "Soft Modulation (50% wet floor)".
#       v2.2 "Stereo Wide (filtered L/R)" applied a time-based
#         exp(-x*5) curve, not a frequency split. Renamed to
#         "Stereo Sweep (time-varying L/R bias)".
#       Added a TRUE Mid-Side mode that decomposes L/R into
#         M = (L+R)/2, S = (L-R)/2, applies the envelope to M
#         only (preserves stereo image of S), then re-encodes.
#   - Visualization rewritten to suite 8x8 standard.
#       Panel A (headline): SSM heatmap.
#       Panel B: Score curve over time.
#       Panel C: Gain envelope (dB) over time.
#       Panel D: Output waveform (L/R for stereo).
#       Panel E: Summary stats bar.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Self-Similarity Resynthesis v3.4.1
    comment === MUSICAL CONTROLS ===
    optionmenu Preset: 2
        option Custom
        option Gentle Resynthesis
        option Glitch Gating
        option Ghost Remix
        option Brutal Novelty
        option Spectral Mosaic
        option Chaotic Tremolo

    optionmenu Creative_mode: 1
        option Standard (Similarity Boost)
        option Inverted (Novelty Extractor)
        option Diagonal Recurrence
        option Hard Quantized (3 levels)
        option Self-Mosaic (Frame Substitution)
    comment (Creative mode is used directly with Custom; named presets set their own.)

    optionmenu Spatial_mode: 2
        option Mono (envelope on mono mix)
        option Preserve Stereo (same envelope both channels)
        option Stereo Sweep (time-varying L/R bias)
        option Rotating (panning effect)
        option Soft Modulation (50% wet floor)
        option True Mid-Side (envelope on M, preserve S)

    comment === RENDER ===
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# HIDDEN DEFAULTS / DETAILS STATE
# ============================================================
# These are the old v3.4 form defaults. They are explicit so the compact main
# form does not change Custom behavior. Named presets then overwrite their recipe
# values, and Edit details opens only afterwards.
speed_mode = 2
time_step = 0.01
analysis_frame_length = 0.03
number_of_MFCCs = 8
similarity_threshold = 0.5
contrast_power = 2.0
high_similarity_boost = 4
low_similarity_attenuation = -8
mask_smoothing_frames = 8
envelope_smoothing_ms = 50
add_chaos = 0.0
hard_threshold_gate = 0
gate_threshold = 0.5
output_gain = 0
normalize_output = 1

# ============================================================
# PRESETS  (numeric matching — fixed in v3.0)
# v3.1: Gentle Resynthesis added as slot 2 (now the default).
# All other preset numbers shifted up by one.
# v3.2.1: named presets override Creative_mode (part of their
# recipe); the override is reported below.
# ============================================================
userCreativeChoice = creative_mode
if preset = 2
    # Gentle Resynthesis — what the description claims the script
    # does. Subtle similarity-driven amplitude shaping rather than
    # aggressive modulation. This is what most users probably want
    # by default.
    creative_mode = 1
    time_step = 0.01
    analysis_frame_length = 0.03
    number_of_MFCCs = 8
    similarity_threshold = 0.5
    contrast_power = 1.5
    mask_smoothing_frames = 8
    hard_threshold_gate = 0
    high_similarity_boost = 4
    low_similarity_attenuation = -4
    add_chaos = 0
    envelope_smoothing_ms = 60
    presetName$ = "Gentle"
elsif preset = 3
    creative_mode = 2
    time_step = 0.005
    analysis_frame_length = 0.02
    number_of_MFCCs = 6
    similarity_threshold = 0.55
    contrast_power = 2.0
    mask_smoothing_frames = 1
    hard_threshold_gate = 1
    gate_threshold = 0.5
    high_similarity_boost = 4
    low_similarity_attenuation = -10
    add_chaos = 0.05
    envelope_smoothing_ms = 4
    presetName$ = "GlitchGating"
elsif preset = 4
    creative_mode = 1
    time_step = 0.008
    analysis_frame_length = 0.025
    similarity_threshold = 0.4
    contrast_power = 2.0
    mask_smoothing_frames = 2
    high_similarity_boost = 10
    low_similarity_attenuation = -12
    envelope_smoothing_ms = 18
    presetName$ = "GhostRemix"
elsif preset = 5
    creative_mode = 2
    time_step = 0.005
    analysis_frame_length = 0.02
    number_of_MFCCs = 5
    similarity_threshold = 0.3
    contrast_power = 2.0
    mask_smoothing_frames = 0
    hard_threshold_gate = 1
    gate_threshold = 0.5
    high_similarity_boost = 5
    low_similarity_attenuation = -12
    add_chaos = 0.08
    envelope_smoothing_ms = 3
    presetName$ = "BrutalNovelty"
elsif preset = 6
    creative_mode = 5
    time_step = 0.02
    analysis_frame_length = 0.05
    similarity_threshold = 0.4
    envelope_smoothing_ms = 10
    presetName$ = "SpectralMosaic"
elsif preset = 7
    creative_mode = 4
    time_step = 0.003
    analysis_frame_length = 0.015
    number_of_MFCCs = 4
    contrast_power = 1.5
    mask_smoothing_frames = 0
    hard_threshold_gate = 0
    gate_threshold = 0.5
    add_chaos = 0.35
    high_similarity_boost = 8
    low_similarity_attenuation = -12
    envelope_smoothing_ms = 4
    presetName$ = "ChaoticTremolo"
else
    presetName$ = "Custom"
endif

# ============================================================
# OPTIONAL DETAILS - values shown AFTER preset loading
# ============================================================
if edit_details
    beginPause: "Self-Similarity Resynthesis v3.4.1 - Details"
        optionmenu: "Analysis bandwidth", speed_mode
        option: "Full-band (original sample rate)"
        option: "16 kHz analysis"
        option: "8 kHz analysis"
        positive: "Time step (s)", time_step
        positive: "Analysis frame length (s)", analysis_frame_length
        integer: "Number of MFCCs", number_of_MFCCs
        real: "Similarity threshold (0..1)", similarity_threshold
        positive: "Contrast power", contrast_power
        positive: "High similarity boost (dB)", high_similarity_boost
        real: "Low similarity attenuation (dB)", low_similarity_attenuation
        integer: "Mask smoothing frames", mask_smoothing_frames
        real: "Envelope smoothing (ms)", envelope_smoothing_ms
        real: "Add chaos (0..1)", add_chaos
        boolean: "Hard threshold gate", hard_threshold_gate
        real: "Gate threshold (0..1)", gate_threshold
        real: "Output gain (dB)", output_gain
        boolean: "Normalize output", normalize_output
    endPause: "Render", 1
    speed_mode = analysis_bandwidth
endif

# === Resolve mode name strings (fix for v2.2 _$ bug) ===
if creative_mode = 1
    creativeName$ = "Standard"
elsif creative_mode = 2
    creativeName$ = "Inverted (Novelty)"
elsif creative_mode = 3
    creativeName$ = "Diagonal Recurrence"
elsif creative_mode = 4
    creativeName$ = "Hard Quantized"
else
    creativeName$ = "Self-Mosaic"
endif

if preset >= 2 and userCreativeChoice <> creative_mode
    # (announced again after clearinfo, in the run header)
    creativeOverridden = 1
else
    creativeOverridden = 0
endif

if spatial_mode = 1
    spatialName$ = "Mono"
elsif spatial_mode = 2
    spatialName$ = "Preserve Stereo"
elsif spatial_mode = 3
    spatialName$ = "Stereo Sweep"
elsif spatial_mode = 4
    spatialName$ = "Rotating"
elsif spatial_mode = 5
    spatialName$ = "Soft Modulation"
else
    spatialName$ = "True Mid-Side"
endif

# ============================================================
# SPEED MODE
# ============================================================
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full-band"
elsif speed_mode = 2
    targetSR = 16000
    speedStr$ = "16 kHz analysis"
else
    targetSR = 8000
    speedStr$ = "8 kHz analysis"
endif

startTime = stopwatch

clearinfo
writeInfoLine: "=== Self-Similarity Resynthesis v3.4.1 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Mode: ", creativeName$
appendInfoLine: "Analysis bandwidth: ", speedStr$
appendInfoLine: "Spatial: ", spatialName$
appendInfoLine: "Preset: ", presetName$
if creativeOverridden
    appendInfoLine: "NOTE: the ", presetName$, " preset sets its own creative mode (",
        ... creativeName$, ") -- the menu selection was overridden. Use Custom to combine freely."
endif
appendInfoLine: ""

# ============================================================
# STEREO HANDLING
# ============================================================
selectObject: originalID
num_channels = Get number of channels
origSR = Get sampling frequency
origDur = Get total duration

appendInfoLine: "Channels: ", num_channels

# Analysis uses one representative channel. Do NOT average channels: an
# anti-phase stereo source can cancel to silence before MFCC extraction.
analysisID = originalID
analysisChannel = 1
if num_channels > 1
    wasStereo = 1
    analysisID = 0
    bestAnalysisRms = -1
    for ch from 1 to num_channels
        selectObject: originalID
        tempAnalysisCh = Extract one channel: ch
        selectObject: tempAnalysisCh
        tempAnalysisRms = Get root-mean-square: 0, 0
        if tempAnalysisRms > bestAnalysisRms
            if analysisID <> 0
                removeObject: analysisID
            endif
            analysisID = tempAnalysisCh
            analysisChannel = ch
            bestAnalysisRms = tempAnalysisRms
        else
            removeObject: tempAnalysisCh
        endif
    endfor
    selectObject: analysisID
    Rename: "ssm_analysis_ch" + string$(analysisChannel)
    appendInfoLine: "Analysis driver: channel ", analysisChannel,
        ... " (highest RMS ", fixed$(bestAnalysisRms, 4), ")"
else
    wasStereo = 0
endif

# Validate the effective recipe after preset overrides.
if time_step <= 0
    exitScript: "Time step must be greater than 0."
endif
if analysis_frame_length <= 0
    exitScript: "Analysis frame length must be greater than 0."
endif
if number_of_MFCCs < 1
    exitScript: "Number of MFCCs must be at least 1."
endif
if similarity_threshold < 0 or similarity_threshold > 1
    exitScript: "Similarity threshold must be between 0 and 1."
endif
if contrast_power <= 0
    exitScript: "Contrast power must be greater than 0."
endif
if mask_smoothing_frames < 0
    exitScript: "Mask smoothing frames must be 0 or greater."
endif
if envelope_smoothing_ms < 0
    exitScript: "Envelope smoothing must be 0 ms or greater."
endif
if add_chaos < 0 or add_chaos > 1
    exitScript: "Chaos amount must be between 0 and 1."
endif
if gate_threshold < 0 or gate_threshold > 1
    exitScript: "Gate threshold must be between 0 and 1."
endif
# Praat's MFCC analysis requires enough audio for its analysis window.
# For this effect a single tiny frame is not meaningful self-similarity anyway.
if origDur < 2 * analysis_frame_length
    exitScript: "Source is too short for this analysis frame length. Use at least " + fixed$(2 * analysis_frame_length, 3) + " s or reduce Analysis frame length."
endif

# Downsample analysis copy if requested
workingID = analysisID
if targetSR > 0 and origSR > targetSR
    appendInfoLine: "[ANALYSIS] Resampling analysis driver to ", targetSR, " Hz"
    selectObject: analysisID
    Resample: targetSR, 50
    workingID = selected("Sound")
endif

selectObject: workingID
duration = Get total duration
sr = Get sampling frequency

# ============================================================
# STAGE 1: EXTRACT FEATURES
# ============================================================
appendInfo: "Stage 1 (MFCCs)... "
selectObject: workingID
To MFCC: number_of_MFCCs, analysis_frame_length, time_step, 100, 100, 0
mfccID = selected("MFCC")

To Matrix
featureID = selected("Matrix")
Rename: "ssm_features"

# featureID layout: nrow = coefficients, ncol = frames
selectObject: featureID
actual_frames = Get number of columns
actual_coeffs = Get number of rows

removeObject: mfccID

appendInfoLine: actual_frames, " frames, ", actual_coeffs, " coeffs"

# ============================================================
# STAGE 2: L2-NORMALIZE EACH FRAME (vectorized)
# ============================================================
# Each frame (column) becomes a unit vector, so the dot product
# in Stage 3 gives cosine similarity directly.
#
# Strategy: compute per-frame norm into a 1×frames helper matrix,
# then normalize via Formula reading from the helper.
# ============================================================
appendInfo: "Stage 2 (normalize, vectorized)... "

# Helper matrix: one row, one cell per frame, holding the L2 norm
Create simple Matrix: "ssm_norms", 1, actual_frames, "0"
normsID = selected("Matrix")

# For each coefficient, accumulate squared values into the norm row
for c from 1 to actual_coeffs
    selectObject: normsID
    Formula: "self + object[" + string$(featureID) + ", " + string$(c) + ", col]^2"
endfor

# Take sqrt and floor at small epsilon to avoid /0
selectObject: normsID
Formula: "if self > 0.0000001 then sqrt(self) else 1 fi"

# Now normalize the feature matrix: divide each cell by its column's norm
Create simple Matrix: "ssm_normalized", actual_coeffs, actual_frames, "0"
normalizedID = selected("Matrix")
Formula: "object[" + string$(featureID) + ", row, col] / object[" + string$(normsID) + ", 1, col]"

removeObject: featureID, normsID
appendInfoLine: "done"

# ============================================================
# STAGE 3: COMPUTE FULL SSM (vectorized)
# ============================================================
# SSM[i,j] = sum over c of (N[c,i] * N[c,j])
#
# One Formula pass per coefficient accumulates that coefficient's
# outer-product contribution into the SSM matrix. No serial
# dependency between cells within one pass — every read is from
# the (untouched) normalized matrix, every write is to the SSM.
# Total: actual_coeffs Formula passes, each O(frames^2) in C++.
# ============================================================
appendInfo: "Stage 3 (SSM, vectorized)... "

Create simple Matrix: "ssm_full", actual_frames, actual_frames, "0"
ssmID = selected("Matrix")

for c from 1 to actual_coeffs
    selectObject: ssmID
    Formula: "self + object[" + string$(normalizedID) + ", " + string$(c) + ", row]"
        ... + " * object[" + string$(normalizedID) + ", " + string$(c) + ", col]"
endfor

appendInfoLine: "done"

# ============================================================
# STAGE 4: PER-FRAME SIMILARITY SCORE (vectorized)
# ============================================================
# Standard mode: score[row] = mean of SSM[row,*] cells > threshold
# Inverted: 1 - standard
# Diagonal: blend with average of nearby diagonal cells
# Hard quantized / Mosaic: handled at gain mapping
#
# We use a helper "thresholded" matrix where each cell is the SSM
# value if above threshold and not on the diagonal, else 0; plus a
# "count" matrix where each cell is 1/0 indicating whether it
# contributed. Row sum of each via Get sum gives numerator and
# count.
# ============================================================
appendInfo: "Stage 4 (scoring, vectorized)... "

# Score vector: actual_frames × 1. v3.3 computes each thresholded row
# directly from the existing SSM instead of allocating TWO additional
# frames×frames matrices. The score law is unchanged; peak memory is not.
Create simple Matrix: "ssm_scores", actual_frames, 1, "0"
scoreID = selected("Matrix")
selectObject: scoreID
Formula: "0"

Create simple Matrix: "ssm_rowtemp", 1, actual_frames, "0"
rowtempID = selected("Matrix")
Create simple Matrix: "ssm_counttemp", 1, actual_frames, "0"
counttempID = selected("Matrix")
ssmStr$ = string$(ssmID)
threshStr$ = fixed$(similarity_threshold, 6)

for r_idx from 1 to actual_frames
    rStr$ = string$(r_idx)
    selectObject: rowtempID
    Formula: "if col <> " + rStr$ + " and object[" + ssmStr$ + ", " + rStr$ + ", col] > " + threshStr$
        ... + " then object[" + ssmStr$ + ", " + rStr$ + ", col] else 0 fi"
    rowSum = Get sum
    
    selectObject: counttempID
    Formula: "if col <> " + rStr$ + " and object[" + ssmStr$ + ", " + rStr$ + ", col] > " + threshStr$
        ... + " then 1 else 0 fi"
    rowCount = Get sum
    
    if rowCount > 0
        score = rowSum / rowCount
    else
        score = 0
    endif
    
    # Apply creative-mode score transformation
    if creative_mode = 2
        # Inverted (novelty)
        score = 1 - score
    elsif creative_mode = 3
        # Diagonal recurrence: blend with mean of ±10 frames diagonal
        diagSum = 0
        diagCount = 0
        for offset from 1 to 10
            if r_idx + offset <= actual_frames
                selectObject: ssmID
                v = Get value in cell: r_idx, r_idx + offset
                diagSum = diagSum + v
                diagCount = diagCount + 1
            endif
            if r_idx - offset >= 1
                selectObject: ssmID
                v = Get value in cell: r_idx, r_idx - offset
                diagSum = diagSum + v
                diagCount = diagCount + 1
            endif
        endfor
        if diagCount > 0
            score = score * 0.5 + (diagSum / diagCount) * 0.5
        endif
    endif
    
    selectObject: scoreID
    Set value: r_idx, 1, score
endfor

removeObject: rowtempID, counttempID
appendInfoLine: "done"

# ============================================================
# STAGE 5: SMOOTHING (vectorized)
# ============================================================
appendInfo: "Stage 5 (smoothing)... "

if mask_smoothing_frames > 0
    # Build smoothed score with a moving average of width mask_smoothing_frames
    # Praat's Matrix doesn't have native convolution; we do it as a
    # loop of (mask_smoothing_frames + 1) Formula accumulations.
    Create simple Matrix: "ssm_smooth", actual_frames, 1, "0"
    smoothID = selected("Matrix")
    Create simple Matrix: "ssm_smooth_count", actual_frames, 1, "0"
    smoothCountID = selected("Matrix")
    
    half = floor(mask_smoothing_frames / 2)
    
    for shift from -half to half
        selectObject: smoothID
        if shift = 0
            Formula: "self + object[" + string$(scoreID) + ", row, 1]"
        elsif shift > 0
            sStr$ = string$(shift)
            Formula: "self + if row + " + sStr$ + " <= " + string$(actual_frames)
                ... + " then object[" + string$(scoreID) + ", row + " + sStr$ + ", 1] else 0 fi"
        else
            sStr$ = string$(-shift)
            Formula: "self + if row - " + sStr$ + " >= 1"
                ... + " then object[" + string$(scoreID) + ", row - " + sStr$ + ", 1] else 0 fi"
        endif
        
        selectObject: smoothCountID
        if shift = 0
            Formula: "self + 1"
        elsif shift > 0
            sStr$ = string$(shift)
            Formula: "self + if row + " + sStr$ + " <= " + string$(actual_frames) + " then 1 else 0 fi"
        else
            sStr$ = string$(-shift)
            Formula: "self + if row - " + sStr$ + " >= 1 then 1 else 0 fi"
        endif
    endfor
    
    selectObject: smoothID
    Formula: "self / object[" + string$(smoothCountID) + ", row, 1]"
    
    removeObject: scoreID, smoothCountID
    scoreID = smoothID
endif
appendInfoLine: "done"

# ============================================================
# STAGE 6: GAIN MAPPING (vectorized)
# ============================================================
appendInfo: "Stage 6 (gain mapping)... "

selectObject: scoreID
s_min = Get minimum
s_max = Get maximum
s_sum = Get sum
s_mean = s_sum / actual_frames

# Measure score spread. Centered scaling is less hostage to one isolated min/max
# frame than v3.3's file-wide min-max normalization.
Create simple Matrix: "ssm_score_deviation", actual_frames, 1, "0"
scoreDevID = selected("Matrix")
meanStr$ = fixed$(s_mean, 10)
selectObject: scoreDevID
Formula: "(object[" + string$(scoreID) + ", row, 1] - " + meanStr$ + ")^2"
scoreSqSum = Get sum
s_std = sqrt(scoreSqSum / actual_frames)
removeObject: scoreDevID

flat_similarity = 0
if s_std < 0.000001
    flat_similarity = 1
endif

Create simple Matrix: "ssm_gain", actual_frames, 1, "0"
gainID = selected("Matrix")

# Build gain in dB. v3.4 named presets are calibrated around this centered mapping:
# score mean -> 0.5, approximately one standard deviation -> 0.18 / 0.82.
# This keeps a few extreme frames from forcing the rest of the file to one end.
selectObject: gainID
chaosStr$ = fixed$(add_chaos, 6)
if flat_similarity
    Formula: "0.5"
else
    stdStr$ = fixed$(s_std, 10)
    Formula: "1 / (1 + exp(-1.5 * (object[" + string$(scoreID) + ", row, 1] - " + meanStr$ + ") / " + stdStr$ + "))"
endif

# Chaos is in normalized 0..1 similarity units, independent of raw score spread.
if add_chaos > 0
    Formula: "self + randomUniform(-1, 1) * " + chaosStr$
    Formula: "if self < 0 then 0 else if self > 1 then 1 else self fi fi"
endif

# Step 3: optional hard gate
if hard_threshold_gate
    gateStr$ = fixed$(gate_threshold, 6)
    Formula: "if self < " + gateStr$ + " then 0 else 1 fi"
endif

# Step 4: optional quantization (creative_mode = 4)
if creative_mode = 4
    Formula: "round(self * 2) / 2"
endif

# Step 5: contrast curve, then map to dB range
contrastStr$ = fixed$(contrast_power, 4)
boostStr$ = fixed$(high_similarity_boost, 4)
attenStr$ = fixed$(low_similarity_attenuation, 4)
Formula: fixed$(low_similarity_attenuation, 4)
    ... + " + (self ^ " + contrastStr$ + ")"
    ... + " * (" + boostStr$ + " - (" + attenStr$ + "))"

selectObject: gainID
gainMinDb = Get minimum
gainMaxDb = Get maximum
gainSumDb = Get sum
gainMeanDb = gainSumDb / actual_frames
appendInfoLine: "done"
appendInfoLine: "Score mean/std: ", fixed$(s_mean, 4), " / ", fixed$(s_std, 4)
if flat_similarity
    appendInfoLine: "NOTE: similarity score is nearly flat; centered map uses neutral 0.5."
endif
if creative_mode <> 5
    appendInfoLine: "Gain map pre-envelope (min / mean / max): ",
        ... fixed$(gainMinDb, 1), " / ", fixed$(gainMeanDb, 1), " / ", fixed$(gainMaxDb, 1), " dB"
endif

# ============================================================
# STAGE 7: RESYNTHESIS
# ============================================================
appendInfo: "Stage 7 (resynthesis)... "

if creative_mode = 5
    # ---- Self-Mosaic mode (vectorized) ----
    # For each frame, find its best non-self match in SSM, then
    # copy that source frame's audio block to the target position.
    # Per-sample Get/Set replaced by Formula (part) block copy.
    appendInfo: " [mosaic]... "
    
    # v3.3: the SSM is driven by one representative channel, but block
    # substitution should not throw away the original stereo/multichannel image.
    # Mono spatial mode explicitly requests mono; every other spatial selection
    # preserves the source channels in Mosaic mode (envelope-specific spatial
    # transforms do not apply because Mosaic has no gain envelope).
    if spatial_mode = 1
        mosaicSourceID = analysisID
        mosaicChannels = 1
        mosaicSpatial$ = "Mono"
    else
        mosaicSourceID = originalID
        mosaicChannels = num_channels
        mosaicSpatial$ = "Preserve source channels"
        if spatial_mode > 2
            appendInfoLine: "NOTE: Self-Mosaic has no gain envelope; spatial mode ", spatialName$,
                ... " falls back to preserving source channels."
        endif
    endif
    selectObject: mosaicSourceID
    workingNS = Get number of samples
    workingDur = Get total duration
    mosaicSR = Get sampling frequency
    
    Create Sound from formula: "Mosaic", mosaicChannels, 0, workingDur, mosaicSR, "0"
    outID = selected("Sound")
    
    frame_samples = round(time_step * mosaicSR)
    
    # Find best match per frame (still per-frame loop, but each
    # iteration just walks one row of SSM via Get value, plus one
    # Formula (part) block copy)
    # v3.2: includes the final frame (the old loop left its block silent)
    for frame from 1 to actual_frames
        selectObject: ssmID
        bestSim = -1
        bestFrame = frame
        # Walk a row (up to ~200 frames is fine; for huge SSMs, sample)
        for other from 1 to actual_frames
            if abs(other - frame) > 5
                v = Get value in cell: frame, other
                if v > bestSim
                    bestSim = v
                    bestFrame = other
                endif
            endif
        endfor
        
        sourceStart = round((bestFrame - 1) * time_step * mosaicSR) + 1
        targetStart = round((frame - 1) * time_step * mosaicSR) + 1
        
        sourceEnd = sourceStart + frame_samples - 1
        targetEnd = targetStart + frame_samples - 1
        if sourceEnd > workingNS
            sourceEnd = workingNS
        endif
        if targetEnd > workingNS
            targetEnd = workingNS
        endif
        
        if targetEnd >= targetStart and sourceEnd >= sourceStart
            # offset = sourceStart - targetStart
            sOff = sourceStart - targetStart
            
            tLo = (targetStart - 1) / mosaicSR
            tHi = targetEnd / mosaicSR
            
            selectObject: outID
            Formula (part): tLo, tHi, 1, mosaicChannels,
                ... "0.7 * object[" + string$(mosaicSourceID) + ", col + " + string$(sOff) + "]"
        endif
    endfor
    
else
    # ---- Envelope-driven resynthesis ----
    # Build envelope at envRate, resample to original SR, multiply
    # v3.1: envRate raised from 100 Hz to 1000 Hz so envelope_smoothing_ms
    # values below ~10 ms actually do work. At 100 Hz, anything under
    # 10 ms rounded to 0 taps and was silently skipped. At 1000 Hz,
    # 1 ms = 1 tap, 50 ms = 50 taps. Memory cost is small — the
    # envelope is a 1-channel Sound, so 1000 Hz × 30 s = 30k samples.
    
    envRate = 1000
    envDuration = origDur
    envFrames = round(envDuration * envRate)
    
    Create Sound from formula: "Envelope", 1, 0, envDuration, envRate, "0"
    envSound = selected("Sound")
    
    # Vectorized fill: for each envelope sample, look up gainID at
    # the corresponding analysis frame
    # col -> envelope sample; t_center = (col - 0.5) / envRate
    # Real-valued frame coord: f = t_center / time_step + 1
    # We linearly interpolate between floor(f) and ceil(f) so adjacent
    # envelope samples don't sit on a staircase. Interpolation is in
    # dB (the gain matrix's native units), which is the perceptually
    # uniform interpolation — linear in linear-amplitude would dip
    # too sharply between high-low pairs.
    selectObject: envSound
    tsStr$ = fixed$(time_step, 8)
    erStr$ = fixed$(envRate, 4)
    afStr$ = string$(actual_frames)
    
    # Build the formula in pieces to keep it readable.
    # f       = (col - 0.5) / envRate / time_step + 1
    # f_lo    = floor(f), clamped to [1, actual_frames]
    # f_hi    = f_lo + 1, clamped to actual_frames
    # frac    = f - f_lo
    # gain_dB = (1 - frac) * gain[f_lo] + frac * gain[f_hi]
    Formula: "10 ^ ("
        ... + "(1 - ((col - 0.5) / " + erStr$ + " / " + tsStr$ + " + 1"
        ... + "      - max(1, min(" + afStr$ + ", floor((col - 0.5) / " + erStr$ + " / " + tsStr$ + " + 1)))) * "
        ... + "object[" + string$(gainID) + ", "
        ... + "max(1, min(" + afStr$ + ", floor((col - 0.5) / " + erStr$ + " / " + tsStr$ + " + 1))), 1]"
        ... + " + ((col - 0.5) / " + erStr$ + " / " + tsStr$ + " + 1"
        ... + "      - max(1, min(" + afStr$ + ", floor((col - 0.5) / " + erStr$ + " / " + tsStr$ + " + 1)))) * "
        ... + "object[" + string$(gainID) + ", "
        ... + "max(1, min(" + afStr$ + ", floor((col - 0.5) / " + erStr$ + " / " + tsStr$ + " + 1) + 1)), 1]"
        ... + ") / 20)"
    
    # ---- Envelope-rate moving-average smoothing ----
    # Operates on the envelope BEFORE it gets resampled to audio rate.
    # Smoothing radius in samples at envRate (1000 Hz in v3.1).
    # 1 ms = 1 tap, 10 ms = 10 taps, 100 ms = 100 taps.
    if envelope_smoothing_ms > 0
        envSmoothTaps = round(envelope_smoothing_ms * envRate / 1000)
        if envSmoothTaps >= 1
            # Build a smoothed copy by accumulating shifted reads of
            # envSound into a fresh sound, then dividing by tap count.
            # Same pattern as the score smoother in Stage 5.
            envSmoothed = Create Sound from formula: "EnvelopeSmoothed", 1, 0, envDuration, envRate, "0"
            
            envHalf = floor(envSmoothTaps / 2)
            envCountSnd = Create Sound from formula: "EnvCount", 1, 0, envDuration, envRate, "0"
            
            srcStr$ = string$(envSound)
            for envShift from -envHalf to envHalf
                selectObject: envSmoothed
                if envShift = 0
                    Formula: "self + object[" + srcStr$ + ", col]"
                elsif envShift > 0
                    sStr$ = string$(envShift)
                    Formula: "self + if col + " + sStr$ + " <= ncol"
                        ... + " then object[" + srcStr$ + ", col + " + sStr$ + "] else 0 fi"
                else
                    sStr$ = string$(-envShift)
                    Formula: "self + if col - " + sStr$ + " >= 1"
                        ... + " then object[" + srcStr$ + ", col - " + sStr$ + "] else 0 fi"
                endif
                
                selectObject: envCountSnd
                if envShift = 0
                    Formula: "self + 1"
                elsif envShift > 0
                    sStr$ = string$(envShift)
                    Formula: "self + if col + " + sStr$ + " <= ncol then 1 else 0 fi"
                else
                    sStr$ = string$(-envShift)
                    Formula: "self + if col - " + sStr$ + " >= 1 then 1 else 0 fi"
                endif
            endfor
            
            selectObject: envSmoothed
            countIDstr$ = string$(envCountSnd)
            Formula: "self / object[" + countIDstr$ + ", col]"
            
            removeObject: envSound, envCountSnd
            envSound = envSmoothed
        endif
    endif
    
    # Resample to original SR
    selectObject: envSound
    Resample: origSR, 50
    envResampled = selected("Sound")
    envName$ = selected$("Sound")
    removeObject: envSound
    
    # Prepare source sound at original SR. Analysis may be downsampled, but
    # audio rendering always starts from the untouched full-rate source.
    selectObject: originalID
    Copy: "ssm_source"
    sourceSound = selected("Sound")
    
    if spatial_mode = 1
        # Mono
        appendInfo: " [mono]... "
        selectObject: sourceSound
        if num_channels > 1
            Convert to mono
            monoSource = selected("Sound")
            removeObject: sourceSound
            sourceSound = monoSource
        endif
        selectObject: sourceSound
        Formula: "self * Sound_'envName$' []"
        outID = selected("Sound")
        removeObject: envResampled
        
    elsif spatial_mode = 2
        # Preserve Stereo (same envelope both channels)
        appendInfo: " [preserve stereo]... "
        selectObject: sourceSound
        Formula: "self * Sound_'envName$' []"
        outID = selected("Sound")
        removeObject: envResampled
        
    elsif spatial_mode = 3
        # Stereo Sweep (time-varying L/R bias) — renamed from
        # v2.2's misleading "Stereo Wide (filtered L/R)"
        appendInfo: " [stereo sweep]... "
        if wasStereo
            selectObject: sourceSound
            Extract left channel
            leftSource = selected("Sound")
            selectObject: sourceSound
            Extract right channel
            rightSource = selected("Sound")
        else
            selectObject: sourceSound
            Copy: "ssm_left"
            leftSource = selected("Sound")
            selectObject: sourceSound
            Copy: "ssm_right"
            rightSource = selected("Sound")
        endif
        
        selectObject: leftSource
        Formula: "self * Sound_'envName$' [] * (1 + 0.3 * exp(-x * 5))"
        leftProc = selected("Sound")
        
        selectObject: rightSource
        Formula: "self * Sound_'envName$' [] * (1 + 0.3 * (1 - exp(-x * 5)))"
        rightProc = selected("Sound")
        
        selectObject: leftProc
        plusObject: rightProc
        Combine to stereo
        outID = selected("Sound")
        
        removeObject: sourceSound, leftSource, rightSource, envResampled
        
    elsif spatial_mode = 4
        # Rotating
        appendInfo: " [rotating]... "
        if wasStereo
            selectObject: sourceSound
            Convert to mono
            monoSource = selected("Sound")
            removeObject: sourceSound
        else
            monoSource = sourceSound
        endif
        
        selectObject: monoSource
        Copy: "ssm_temp"
        tempSound = selected("Sound")
        Formula: "self * Sound_'envName$' []"
        
        selectObject: tempSound
        Copy: "ssm_left"
        leftSound = selected("Sound")
        Formula: "self * (0.6 + 0.4 * cos(2 * pi * 0.2 * x))"
        
        selectObject: tempSound
        Copy: "ssm_right"
        rightSound = selected("Sound")
        Formula: "self * (0.6 + 0.4 * sin(2 * pi * 0.2 * x))"
        
        selectObject: leftSound
        plusObject: rightSound
        Combine to stereo
        outID = selected("Sound")
        
        removeObject: monoSource, tempSound, leftSound, rightSound, envResampled
        
    elsif spatial_mode = 5
        # Soft Modulation (50% wet floor) — renamed from v2.2's
        # mislabeled "Mid-Side". This is what the code actually
        # did: AM with a DC offset, no mid/side decomposition.
        appendInfo: " [soft mod]... "
        selectObject: sourceSound
        Formula: "self * (0.5 + 0.5 * Sound_'envName$' [])"
        outID = selected("Sound")
        removeObject: envResampled
        
    else
        # True Mid-Side (NEW in v3.0)
        # Decompose: M = (L+R)/2, S = (L-R)/2
        # Apply env to M only; preserve S; recombine: L' = M' + S, R' = M' - S
        appendInfo: " [true M/S]... "
        if wasStereo
            selectObject: sourceSound
            Extract left channel
            sLid = selected("Sound")
            selectObject: sourceSound
            Extract right channel
            sRid = selected("Sound")
            
            # Build mid = 0.5*(L+R), apply envelope; side = 0.5*(L-R) untouched
            selectObject: sLid
            sNS = Get number of samples
            sDur = Get total duration
            
            # midSound starts as L
            selectObject: sLid
            Copy: "ssm_mid"
            midSound = selected("Sound")
            Formula: "0.5 * (self + object[" + string$(sRid) + ", col])"
            Formula: "self * Sound_'envName$' []"
            
            # sideSound = 0.5*(L-R)
            selectObject: sLid
            Copy: "ssm_side"
            sideSound = selected("Sound")
            Formula: "0.5 * (self - object[" + string$(sRid) + ", col])"
            
            # Recombine
            selectObject: midSound
            Copy: "ssm_recL"
            recL = selected("Sound")
            Formula: "self + object[" + string$(sideSound) + ", col]"
            
            selectObject: midSound
            Copy: "ssm_recR"
            recR = selected("Sound")
            Formula: "self - object[" + string$(sideSound) + ", col]"
            
            selectObject: recL
            plusObject: recR
            Combine to stereo
            outID = selected("Sound")
            
            removeObject: sourceSound, sLid, sRid, midSound, sideSound, envResampled
        else
            # Mono input — degrade gracefully to Preserve Stereo
            appendInfo: " (mono input, falling back to preserve)... "
            selectObject: sourceSound
            Formula: "self * Sound_'envName$' []"
            outID = selected("Sound")
            removeObject: envResampled
        endif
    endif
endif

selectObject: outID
Rename: originalName$ + "_similarity_" + presetName$
appendInfoLine: "done"

# ============================================================
# FINALIZE
# ============================================================
selectObject: outID

if normalize_output
    preNormPeak = Get absolute extremum: 0, 0, "None"
    if preNormPeak > 1e-15
        Scale peak: 0.95
    endif
endif

if output_gain <> 0
    Scale: 10 ^ (output_gain / 20)
endif

# Positive post-normalization gain can otherwise create samples beyond full scale.
postGainPeak = Get absolute extremum: 0, 0, "None"
if postGainPeak > 1
    appendInfoLine: "NOTE: post-gain peak ", fixed$(postGainPeak, 3),
        ... " exceeded 1.0; peak-safe scaled to 0.999."
    Scale peak: 0.999
endif

processingTime = stopwatch - startTime
selectObject: outID
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing..."
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##SELF-SIMILARITY SPECTRAL RESYNTHESIS v3.4.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + creativeName$
        ... + "  |  " + spatialName$
        ... + "  |  " + string$(actual_frames) + " frames"
        ... + "  |  " + fixed$(processingTime, 2) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: SSM HEATMAP  (left, headline)
    # Vectorized rendering: instead of per-cell Paint rectangle,
    # we use the panel's full-res grid and let Praat draw rows.
    # For visual cell sizing, we still need a render stride if
    # actual_frames is huge. Cap at 200x200 visual cells.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, actual_frames, 0, actual_frames
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actual_frames, 0, actual_frames
    
    # Decide rendering stride to keep Paint rectangle count manageable
    visCells = 120
    if actual_frames < visCells
        visStride = 1
    else
        visStride = ceiling(actual_frames / visCells)
    endif
    
    selectObject: ssmID
    r_vis = 1
    while r_vis <= actual_frames
        rEnd = r_vis + visStride - 1
        if rEnd > actual_frames
            rEnd = actual_frames
        endif
        c_vis = 1
        while c_vis <= actual_frames
            cEnd = c_vis + visStride - 1
            if cEnd > actual_frames
                cEnd = actual_frames
            endif
            v = Get value in cell: r_vis, c_vis
            # Diverging-ish: low = blue, high = red, mid = light
            if v < 0
                v = 0
            endif
            if v > 1
                v = 1
            endif
            cR = 0.30 + v * 0.65
            cG = 0.50 - v * 0.30
            cB = 0.85 - v * 0.65
            if cG < 0
                cG = 0
            endif
            if cB < 0
                cB = 0
            endif
            clr$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
            Paint rectangle: clr$, r_vis - 1, rEnd, c_vis - 1, cEnd
            c_vis = c_vis + visStride
        endwhile
        r_vis = r_vis + visStride
    endwhile
    
    # Diagonal reference
    Colour: "{0.20, 0.20, 0.20}"
    Line width: 1
    Draw line: 0, 0, actual_frames, actual_frames
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Frame"
    Text bottom: "yes", "Frame"
    
    # ----------------------------------------------------------
    # PANEL B: SCORE CURVE  (right, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.90, 2.85
    
    selectObject: scoreID
    sMinV = Get minimum
    sMaxV = Get maximum
    if sMaxV - sMinV < 0.001
        sMaxV = sMinV + 0.001
    endif
    sPad = (sMaxV - sMinV) * 0.10
    
    Axes: 0, actual_frames, sMinV - sPad, sMaxV + sPad
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, actual_frames, sMinV - sPad, sMaxV + sPad
    
    # Similarity threshold applies to raw SSM cells BEFORE row averaging,
    # so drawing it as a horizontal SCORE threshold would be misleading.
    
    # Score line — sample at most 400 points
    drawN = actual_frames
    if drawN > 400
        drawStride = ceiling(drawN / 400)
    else
        drawStride = 1
    endif
    
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 1.2
    selectObject: scoreID
    prevR = 1
    prevV = Get value in cell: 1, 1
    r = 1 + drawStride
    while r <= actual_frames
        v = Get value in cell: r, 1
        Draw line: prevR, prevV, r, v
        prevR = r
        prevV = v
        r = r + drawStride
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Score"
    Text bottom: "yes", "Frame"
    
    # ----------------------------------------------------------
    # PANEL C: GAIN ENVELOPE (dB)  (right, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    selectObject: gainID
    gMinV = Get minimum
    gMaxV = Get maximum
    if gMaxV - gMinV < 0.5
        gMaxV = gMinV + 0.5
    endif
    gPad = (gMaxV - gMinV) * 0.08
    
    Axes: 0, actual_frames, gMinV - gPad, gMaxV + gPad
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, actual_frames, gMinV - gPad, gMaxV + gPad
    
    # 0 dB reference
    if gMinV - gPad < 0 and gMaxV + gPad > 0
        Colour: "{0.55, 0.55, 0.55}"
        Dotted line
        Draw line: 0, 0, actual_frames, 0
        Solid line
    endif
    
    # Configured boost / atten reference levels
    Colour: "{0.85, 0.85, 0.88}"
    Dotted line
    Draw line: 0, high_similarity_boost, actual_frames, high_similarity_boost
    Draw line: 0, low_similarity_attenuation, actual_frames, low_similarity_attenuation
    Solid line
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    Text: actual_frames * 0.99, "right", high_similarity_boost, "bottom",
        ... "boost = " + fixed$(high_similarity_boost, 0) + " dB"
    Text: actual_frames * 0.99, "right", low_similarity_attenuation, "top",
        ... "atten = " + fixed$(low_similarity_attenuation, 0) + " dB"
    
    Colour: "{0.85, 0.40, 0.20}"
    Line width: 1.2
    selectObject: gainID
    prevR = 1
    prevV = Get value in cell: 1, 1
    r = 1 + drawStride
    while r <= actual_frames
        v = Get value in cell: r, 1
        Draw line: prevR, prevV, r, v
        prevR = r
        prevV = v
        r = r + drawStride
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain (dB)"
    Text bottom: "yes", "Frame"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.20, "centre", 7.30, "half", "Self-similarity matrix (red = high, blue = low)"
    Text: 6.10, "centre", 7.30, "half", "Score (upper) & gain envelope (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: outID
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: outID
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.50}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        selectObject: outID
        Extract one channel: 2
        vCh2 = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh2
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  (blue = L,  orange = R)"
    else
        Text top: "no", "Output"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + creativeName$
        ... + "  |  Spatial: " + spatialName$
        ... + "  |  " + speedStr$
        ... + "  |  Frames: " + string$(actual_frames)
        ... + "  |  MFCCs: " + string$(actual_coeffs)
        ... + "  |  Step: " + fixed$(time_step * 1000, 1) + " ms"
        ... + "  |  Score scale: centered"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Threshold: " + fixed$(similarity_threshold, 2)
        ... + "  |  Contrast: " + fixed$(contrast_power, 1)
        ... + "  |  Boost / atten: " + fixed$(high_similarity_boost, 0) + " / " + fixed$(low_similarity_attenuation, 0) + " dB"
        ... + "  |  Smooth: " + string$(mask_smoothing_frames) + " fr / " + fixed$(envelope_smoothing_ms, 1) + " ms env"
        ... + "  |  Chaos: " + fixed$(add_chaos, 2)
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Time: " + fixed$(processingTime, 2) + " s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: normalizedID, ssmID, scoreID, gainID

if analysisID <> originalID
    removeObject: analysisID
endif
if workingID <> analysisID
    removeObject: workingID
endif

selectObject: outID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    selectObject: outID
    Play
endif

selectObject: outID
