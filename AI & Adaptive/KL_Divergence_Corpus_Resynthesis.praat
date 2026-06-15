# ========================================================================================
# Praat AudioTools - KL_Divergence_Corpus_Resynthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Information-theoretic corpus mosaicking. Corpus A is the REFERENCE;
#   Corpus B is the SOURCE material. The script estimates the feature
#   distribution P of Corpus A as per-dimension normalised histograms,
#   segments Corpus B into grains, then GREEDILY builds an output sound
#   by repeatedly choosing the Corpus-B grain that, when added, minimises
#   the KL divergence between P and the running output distribution Q.
#   KL actively drives synthesis - it is not computed after the fact.
#
#   Distribution model: per-feature normalised histograms (NOT GMMs).
#   This is the feasible and honest choice inside Praat.
#
#   Features per frame (default 16 dims): MFCC c1..cK, RMS (dB),
#   spectral centroid, spectral spread.
#   KL modes: forward D(P||Q), reverse D(Q||P), symmetric.
#
#   Storage uses Praat Matrix / TableOfReal objects (no fragile
#   interpolated variable names).
#
# Category: Concatenative / Information-Theoretic Synthesis
# ========================================================================================

form KL Divergence Corpus Resynthesis
    comment === Corpora (leave blank for a chooser) ===
    sentence Corpus_A_folder
    comment (reference: the distribution to MATCH)
    sentence Corpus_B_folder
    comment (source: the grains to BUILD FROM)
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Coarse / fast
        option Balanced
        option Fine match
        option Dense mosaic
    comment === Analysis ===
    positive Target_sample_rate 44100
    positive Frame_length 0.0464
    optionmenu Overlap_ratio: 2
        option 1:1  (no overlap)
        option 1:2  (50% overlap)
        option 1:4  (75% overlap)
        option 1:8  (87.5% overlap)
    integer Number_of_mfcc 13
    integer Histogram_bins 32
    comment === KL ===
    optionmenu Kl_mode: 3
        option Forward  D(P||Q)
        option Reverse  D(Q||P)
        option Symmetric
    real Kl_epsilon 0.000001
    comment === Output ===
    positive Output_duration 8.0
    positive Crossfade 0.01
    integer Random_seed 12345
    positive Candidate_pool 40
    comment (Corpus-B grains tried per output step; 0 = all)
    integer Max_files_per_corpus 4
    comment (cap files loaded per corpus; 0 = no limit)
    comment === Output options ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ========================================================================================
# PRESETS  (option 1 = Custom: keep the form values; others override the
#   key dials - histogram bins, candidate pool, KL mode, granularity)
# ========================================================================================
if preset = 2
    # Coarse / fast: fewer bins, small pool, forward KL
    histogram_bins = 16
    candidate_pool = 20
    kl_mode = 1
    presetName$ = "Coarse"
elsif preset = 3
    # Balanced
    histogram_bins = 32
    candidate_pool = 40
    kl_mode = 3
    presetName$ = "Balanced"
elsif preset = 4
    # Fine match: more bins, larger pool, symmetric
    histogram_bins = 48
    candidate_pool = 80
    kl_mode = 3
    presetName$ = "Fine"
elsif preset = 5
    # Dense mosaic: finer overlap -> more, shorter-spaced grains
    histogram_bins = 32
    candidate_pool = 60
    kl_mode = 3
    overlap_ratio = 3
    presetName$ = "Dense"
else
    presetName$ = "Custom"
endif

# Derive hop_size from the frame:hop overlap ratio (1:1 / 1:2 / 1:4 / 1:8).
if overlap_ratio = 1
    hopDiv = 1
elsif overlap_ratio = 2
    hopDiv = 2
elsif overlap_ratio = 3
    hopDiv = 4
else
    hopDiv = 8
endif
hop_size = frame_length / hopDiv

clearinfo
writeInfoLine: "=== KL Divergence Corpus Resynthesis v1.0 ==="
appendInfoLine: ""

random_initializeWithSeedUnsafelyButPredictably: random_seed

# ---- resolve folders ----
dirA$ = corpus_A_folder$
if dirA$ = ""
    dirA$ = chooseDirectory$: "Choose Corpus A (REFERENCE)"
    if dirA$ = ""
        exitScript: "No Corpus A folder chosen."
    endif
endif
dirB$ = corpus_B_folder$
if dirB$ = ""
    dirB$ = chooseDirectory$: "Choose Corpus B (SOURCE material)"
    if dirB$ = ""
        exitScript: "No Corpus B folder chosen."
    endif
endif
@ensureSlash: dirA$
dirA$ = ensureSlash.out$
@ensureSlash: dirB$
dirB$ = ensureSlash.out$

# Feature layout: columns 1..K = MFCC, K+1 = RMS, K+2 = centroid, K+3 = spread
nMfcc = number_of_mfcc
featDim = nMfcc + 3
colRMS = nMfcc + 1
colCEN = nMfcc + 2
colSPR = nMfcc + 3
nBins = histogram_bins
eps = kl_epsilon

appendInfoLine: "Corpus A: ", dirA$
appendInfoLine: "Corpus B: ", dirB$
appendInfoLine: "Feature dimensions: ", featDim, " (", nMfcc,
    ... " MFCC + RMS + centroid + spread)"
appendInfoLine: "Histogram bins/feature: ", nBins
appendInfoLine: "Frame: ", fixed$(frame_length * 1000, 1), " ms   hop: ",
    ... fixed$(hop_size * 1000, 1), " ms   (overlap 1:", hopDiv, ")"
appendInfoLine: ""

procedure ensureSlash: .p$
    .out$ = .p$
    if right$(.out$, 1) <> "/" and right$(.out$, 1) <> "\"
        if index(.out$, "\") > 0
            .out$ = .out$ + "\"
        else
            .out$ = .out$ + "/"
        endif
    endif
endproc

# ----------------------------------------------------------------------------------------
# Extract per-frame features of ONE sound into a fresh TableOfReal
# (rows = frames, cols = featDim). Also returns parallel time data via
# columns in a metadata TableOfReal if .keepMeta = 1.
# Sets: ef.featTable (TableOfReal id, may be 0 if no frames)
#       ef.metaTable (TableOfReal id with cols: t0, t1) if keepMeta
#       ef.nFrames
# ----------------------------------------------------------------------------------------
procedure extractOne: .soundID, .keepMeta
    selectObject: .soundID
    .dur = Get total duration
    .featTable = 0
    .metaTable = 0
    .nFrames = 0
    if .dur < frame_length + hop_size
        goto EO_DONE
    endif

    selectObject: .soundID
    .mfcc = To MFCC: nMfcc, frame_length, hop_size, 100, 100, 0.0
    selectObject: .soundID
    .intens = To Intensity: 100, hop_size, "yes"
    selectObject: .soundID
    .spec = To Spectrogram: frame_length, 5500, hop_size, 20, "Gaussian"
    # Convert the spectrogram to a Matrix ONCE (rows = freq bins, cols =
    # time frames). Spectral centroid/spread are then computed per frame
    # by array math over a column - no per-frame Spectrum objects.
    selectObject: .spec
    .specMat = To Matrix
    .nFreq = Get number of rows
    .nTime = Get number of columns
    .freqStep = Get row distance
    .freq0 = Get y of row: 1
    .specT0 = Get x of column: 1
    .timeStep = Get column distance

    selectObject: .mfcc
    .nfr = Get number of frames

    # count valid frames first
    .valid = 0
    for .fr to .nfr
        selectObject: .mfcc
        .t = Get time from frame number: .fr
        if .t > hop_size/2 and .t < .dur - hop_size/2
            .valid = .valid + 1
        endif
    endfor
    if .valid < 1
        removeObject: .mfcc, .intens, .spec, .specMat
        goto EO_DONE
    endif

    .featTable = Create TableOfReal: "feat_tmp", .valid, featDim
    if .keepMeta = 1
        .metaTable = Create TableOfReal: "meta_tmp", .valid, 2
    endif

    .row = 0
    for .fr to .nfr
        selectObject: .mfcc
        .t = Get time from frame number: .fr
        if .t > hop_size/2 and .t < .dur - hop_size/2
            .row = .row + 1
            for .c to nMfcc
                selectObject: .mfcc
                .v = Get value in frame: .fr, .c
                if .v = undefined
                    .v = 0
                endif
                selectObject: .featTable
                Set value: .row, .c, .v
            endfor
            selectObject: .intens
            .db = Get value at time: .t, "Cubic"
            if .db = undefined
                .db = 0
            endif
            # --- spectral centroid + spread from the spectrogram Matrix ---
            # find the nearest spectrogram time column to .t
            .col = round((.t - .specT0) / .timeStep) + 1
            if .col < 1
                .col = 1
            endif
            if .col > .nTime
                .col = .nTime
            endif
            selectObject: .specMat
            .sumP = 0
            .sumFP = 0
            for .fb to .nFreq
                .pw = Get value in cell: .fb, .col
                if .pw < 0
                    .pw = 0
                endif
                .fHz = .freq0 + (.fb - 1) * .freqStep
                .sumP = .sumP + .pw
                .sumFP = .sumFP + .fHz * .pw
            endfor
            if .sumP > 0
                .cen = .sumFP / .sumP
                .vsum = 0
                for .fb to .nFreq
                    .pw = Get value in cell: .fb, .col
                    if .pw < 0
                        .pw = 0
                    endif
                    .fHz = .freq0 + (.fb - 1) * .freqStep
                    .vsum = .vsum + .pw * (.fHz - .cen) * (.fHz - .cen)
                endfor
                .spr = sqrt(.vsum / .sumP)
            else
                .cen = 0
                .spr = 0
            endif
            selectObject: .featTable
            Set value: .row, colRMS, .db
            Set value: .row, colCEN, .cen
            Set value: .row, colSPR, .spr
            if .keepMeta = 1
                .t0 = .t - frame_length/2
                .t1 = .t + frame_length/2
                if .t0 < 0
                    .t0 = 0
                endif
                if .t1 > .dur
                    .t1 = .dur
                endif
                selectObject: .metaTable
                Set value: .row, 1, .t0
                Set value: .row, 2, .t1
            endif
        endif
    endfor
    .nFrames = .valid
    removeObject: .mfcc, .intens, .spec, .specMat
    label EO_DONE
endproc

# ----------------------------------------------------------------------------------------
# Load a corpus folder and build a master feature TableOfReal.
#   WAV/AIFF/MP3 -> mono -> resample -> peak-normalise -> extractOne.
#   Per-sound feature tables are collected, then copied into one master.
#   For Corpus B (keepMeta=1) we also build a master meta table (t0,t1)
#   and a grainSnd Matrix (1 col) holding the source Sound id per grain.
# Sets: lc.feat (master TableOfReal), lc.meta, lc.snd (Matrix of ids),
#       lc.nRows, lc.files, lc.kept (count of kept B sounds)
#       lc.keptMat (Matrix of kept sound ids) when keepMeta=1
# ----------------------------------------------------------------------------------------
procedure loadCorpus: .dir$, .keepMeta
    .files = 0
    .skipped = 0
    .nTabs = 0
    .totalRows = 0
    .kept = 0

    # temporary holders (Matrix as a growable-ish list via fixed cap)
    .capTabs = 100000
    # file cap (0 = no limit)
    .cap = max_files_per_corpus
    for .ext to 4
        if .ext = 1
            .pat$ = "*.wav"
        elsif .ext = 2
            .pat$ = "*.aiff"
        elsif .ext = 3
            .pat$ = "*.aif"
        else
            .pat$ = "*.mp3"
        endif
        .list$# = fileNames_caseInsensitive$#(.dir$ + .pat$)
        .nf = size(.list$#)
        for .i to .nf
            # honour the file cap (0 = no limit). Praat 'for' can't break,
            # so once capped we simply stop processing further files.
            if .cap = 0 or .files < .cap
            .fn$ = .list$#[.i]
            nocheck Read from file: .dir$ + .fn$
            if numberOfSelected("Sound") = 1
                .sid = selected("Sound")
                .nm$ = selected$("Sound")
                .ch = Get number of channels
                if .ch > 1
                    Convert to mono
                    .m = selected("Sound")
                    removeObject: .sid
                    .sid = .m
                endif
                selectObject: .sid
                .sr = Get sampling frequency
                if .sr <> target_sample_rate
                    Resample: target_sample_rate, 50
                    .rs = selected("Sound")
                    removeObject: .sid
                    .sid = .rs
                endif
                selectObject: .sid
                Rename: .nm$
                Scale peak: 0.99
                .d = Get total duration
                if .d < frame_length + hop_size
                    .skipped = .skipped + 1
                    removeObject: .sid
                else
                    @extractOne: .sid, .keepMeta
                    if extractOne.nFrames > 0
                        .files = .files + 1
                        .nTabs = .nTabs + 1
                        tabId_'.nTabs' = extractOne.featTable
                        tabRows_'.nTabs' = extractOne.nFrames
                        tabSnd_'.nTabs' = .sid
                        if .keepMeta = 1
                            tabMeta_'.nTabs' = extractOne.metaTable
                        endif
                        .totalRows = .totalRows + extractOne.nFrames
                    endif
                    if .keepMeta = 1
                        .kept = .kept + 1
                        keptId_'.kept' = .sid
                    else
                        removeObject: .sid
                    endif
                endif
            endif
            endif
        endfor
    endfor

    if .skipped > 0
        appendInfoLine: "  (", .skipped, " file(s) skipped: too short)"
    endif

    .nRows = .totalRows
    if .totalRows < 1
        .feat = 0
        goto LC_DONE
    endif

    # build master feature table (+ meta + snd-id matrix)
    .feat = Create TableOfReal: "master_feat", .totalRows, featDim
    if .keepMeta = 1
        .meta = Create TableOfReal: "master_meta", .totalRows, 2
        .snd = Create simple Matrix: "master_snd", .totalRows, 1, "0"
    endif

    .w = 0
    for .ti to .nTabs
        .ft = tabId_'.ti'
        .rw = tabRows_'.ti'
        .sndId = tabSnd_'.ti'
        if .keepMeta = 1
            .mt = tabMeta_'.ti'
        endif
        for .r to .rw
            .w = .w + 1
            for .c to featDim
                selectObject: .ft
                .val = Get value: .r, .c
                selectObject: .feat
                Set value: .w, .c, .val
            endfor
            if .keepMeta = 1
                selectObject: .mt
                .a0 = Get value: .r, 1
                .a1 = Get value: .r, 2
                selectObject: .meta
                Set value: .w, 1, .a0
                Set value: .w, 2, .a1
                selectObject: .snd
                Set value: .w, 1, .sndId
            endif
        endfor
        removeObject: .ft
        if .keepMeta = 1
            removeObject: .mt
        endif
    endfor
    label LC_DONE
endproc

# ========================================================================================
# LOAD BOTH CORPORA
# ========================================================================================

appendInfoLine: "[1/5] Analysing Corpus A (reference)..."
@loadCorpus: dirA$, 0
aFeat = loadCorpus.feat
nAFrames = loadCorpus.nRows
nAFiles = loadCorpus.files
if nAFrames < 1
    exitScript: "Corpus A produced no usable frames. Check the folder."
endif
appendInfoLine: "  Corpus A: ", nAFiles, " file(s), ", nAFrames, " frames."
if max_files_per_corpus > 0
    appendInfoLine: "    (file cap: ", max_files_per_corpus, " per corpus)"
endif

appendInfoLine: "[2/5] Analysing Corpus B (source grains)..."
@loadCorpus: dirB$, 1
bFeat = loadCorpus.feat
bMeta = loadCorpus.meta
bSnd = loadCorpus.snd
nBGrains = loadCorpus.nRows
nBFiles = loadCorpus.files
nBKept = loadCorpus.kept
if nBGrains < 1
    exitScript: "Corpus B produced no usable grains. Check the folder."
endif
appendInfoLine: "  Corpus B: ", nBFiles, " file(s), ", nBGrains, " grains."

approxNeeded = ceiling(output_duration / hop_size)
if nBGrains < approxNeeded / 4
    appendInfoLine: "  WARNING: only ", nBGrains, " grains for ~",
        ... approxNeeded, " output steps; grains will be reused heavily."
endif

# ========================================================================================
# STAGE 3: GLOBAL BIN EDGES + REFERENCE DISTRIBUTION P
#   Edges per dim from COMBINED A+B range (shared support for KL).
#   P[d][bin] = normalised, eps-smoothed histogram of Corpus A.
#   Stored in Matrix objects: pMat (featDim x nBins), and edge vectors
#   dimLo#, dimW# (Praat vectors).
# ========================================================================================

appendInfoLine: "[3/5] Building reference distribution P..."

dimLo# = zero#(featDim)
dimHi# = zero#(featDim)
for d to featDim
    dimLo#[d] = 1e30
    dimHi#[d] = -1e30
endfor

# Per-dimension min/max. TableOfReal has no column-min/max query, so we
# scan rows - but read each row as a vector (one call/frame) with the
# table selected once, so it stays fast.
selectObject: aFeat
for i to nAFrames
    for d to featDim
        v = Get value: i, d
        if v < dimLo#[d]
            dimLo#[d] = v
        endif
        if v > dimHi#[d]
            dimHi#[d] = v
        endif
    endfor
endfor
selectObject: bFeat
for i to nBGrains
    for d to featDim
        v = Get value: i, d
        if v < dimLo#[d]
            dimLo#[d] = v
        endif
        if v > dimHi#[d]
            dimHi#[d] = v
        endif
    endfor
endfor

dimW# = zero#(featDim)
for d to featDim
    if dimHi#[d] <= dimLo#[d]
        dimHi#[d] = dimLo#[d] + 1
    endif
    dimW#[d] = (dimHi#[d] - dimLo#[d]) / nBins
endfor

# bin index of a value in dimension d (1..nBins)
procedure binOf: .val, .d
    .b = floor((.val - dimLo#[.d]) / dimW#[.d]) + 1
    if .b < 1
        .b = 1
    endif
    if .b > nBins
        .b = nBins
    endif
    .out = .b
endproc

# P histogram: accumulate counts in a plain matrix-free vector per dim,
# reading each aFeat row as a vector (one call), no per-cell selectObject.
pMat = Create simple Matrix: "Pdist", featDim, nBins, "0"
# flat count buffer: index (d-1)*nBins + b
pCount# = zero#(featDim * nBins)
selectObject: aFeat
for i to nAFrames
    for d to featDim
        v = Get value: i, d
        @binOf: v, d
        idx = (d - 1) * nBins + binOf.out
        pCount#[idx] = pCount#[idx] + 1
    endfor
endfor
# eps-smooth + normalise, write once into pMat
selectObject: pMat
for d to featDim
    psum = 0
    for b to nBins
        c = pCount#[(d - 1) * nBins + b] + eps
        pCount#[(d - 1) * nBins + b] = c
        psum = psum + c
    endfor
    for b to nBins
        Set value: d, b, pCount#[(d - 1) * nBins + b] / psum
    endfor
endfor

# Precompute each B grain's bin index per dim into a Matrix (write per row).
bBinMat = Create simple Matrix: "Bbins", nBGrains, featDim, "0"
for i to nBGrains
    selectObject: bFeat
    bins# = zero#(featDim)
    for d to featDim
        v = Get value: i, d
        @binOf: v, d
        bins#[d] = binOf.out
    endfor
    selectObject: bBinMat
    for d to featDim
        Set value: i, d, bins#[d]
    endfor
endfor
appendInfoLine: "  P built (", featDim, " dims x ", nBins, " bins)."

# ========================================================================================
# STAGE 5: KL-GUIDED GREEDY CONSTRUCTION
#   Q counts in a flat vector qVec# (no objects in the hot loop), total
#   grain we simulate adding it (its one bin per dim +1, total +1),
#   compute averaged KL(P,Q'), pick the minimum, then commit.
# ========================================================================================

appendInfoLine: "[4/5] KL-guided selection..."

# ----- cache everything the hot loop needs into flat Praat vectors so
#       the inner KL computation touches NO objects (selectObject and
#       Get value in cell were the bottleneck). Index helpers:
#         P/Q cell (d,b) -> (d-1)*nBins + b
#         B grain g dim d -> (g-1)*featDim + d
pVec# = zero#(featDim * nBins)
pLogVec# = zero#(featDim * nBins)
selectObject: pMat
for d to featDim
    for b to nBins
        pv = Get value in cell: d, b
        pVec#[(d - 1) * nBins + b] = pv
        pLogVec#[(d - 1) * nBins + b] = ln(pv)
    endfor
endfor

# B-grain bins + metadata, read once
bBin# = zero#(nBGrains * featDim)
selectObject: bBinMat
for g to nBGrains
    for d to featDim
        bBin#[(g - 1) * featDim + d] = Get value in cell: g, d
    endfor
endfor
bSndArr# = zero#(nBGrains)
bT0Arr# = zero#(nBGrains)
bT1Arr# = zero#(nBGrains)
selectObject: bSnd
for g to nBGrains
    bSndArr#[g] = Get value in cell: g, 1
endfor
selectObject: bMeta
for g to nBGrains
    bT0Arr#[g] = Get value: g, 1
    bT1Arr#[g] = Get value: g, 2
endfor

# Running output histogram as a flat vector (counts), total qTotal.
qVec# = zero#(featDim * nBins)
qTotal = 0

# KL of (P, Q + one simulated grain). addBin#[d] = bin to add in dim d,
# or -1 for "no addition". Pure vector arithmetic - no object access.
# klDir: 1 forward D(P||Q), 2 reverse D(Q||P), 3 symmetric.
procedure klScore: .klDir
    .denom = qTotal + 1 + nBins * eps
    .lnDenom = ln(.denom)
    .sum = 0
    for .d to featDim
        .addb = addBin#[.d]
        .base = (.d - 1) * nBins
        .klf = 0
        .klr = 0
        for .b to nBins
            .k = .base + .b
            .qc = qVec#[.k] + eps
            if .b = .addb
                .qc = .qc + 1
            endif
            .q = .qc / .denom
            .p = pVec#[.k]
            if .klDir = 1 or .klDir = 3
                .klf = .klf + .p * (pLogVec#[.k] - ln(.q))
            endif
            if .klDir = 2 or .klDir = 3
                .klr = .klr + .q * (ln(.q) - pLogVec#[.k])
            endif
        endfor
        if .klDir = 1
            .sum = .sum + .klf
        elsif .klDir = 2
            .sum = .sum + .klr
        else
            .sum = .sum + 0.5 * (.klf + .klr)
        endif
    endfor
    .out = .sum / featDim
endproc

# initial KL (no addition)
addBin# = zero#(featDim)
for d to featDim
    addBin#[d] = -1
endfor
@klScore: kl_mode
klInitial = klScore.out

stepHop = hop_size
nSteps = ceiling(output_duration / stepHop)
if nSteps < 1
    nSteps = 1
endif
poolSize = candidate_pool
if poolSize <= 0 or poolSize > nBGrains
    poolSize = nBGrains
endif

selSnd# = zero#(nSteps)
selT0# = zero#(nSteps)
selT1# = zero#(nSteps)
nSel = 0

for step to nSteps
    # ---- precompute, once per step, the base KL per dimension and the
    #      per-bin CORRECTION that adding one grain to that bin produces.
    #      A candidate's KL = (1/featDim) * sum_d (base_d + corr_d[addbin]).
    #      denom is identical for all candidates this step.
    denom = qTotal + 1 + nBins * eps
    lnDenom = ln(denom)
    baseSum = 0
    for d to featDim
        b0 = (d - 1) * nBins
        f0 = 0
        for b to nBins
            k = b0 + b
            qn = qVec#[k] + eps
            q = qn / denom
            p = pVec#[k]
            lnq = ln(q)
            if kl_mode = 1
                f0 = f0 + p * (pLogVec#[k] - lnq)
            elsif kl_mode = 2
                f0 = f0 + q * (lnq - pLogVec#[k])
            else
                f0 = f0 + 0.5 * (p * (pLogVec#[k] - lnq) + q * (lnq - pLogVec#[k]))
            endif
        endfor
        baseSum = baseSum + f0
        # correction for adding +1 to each possible bin a in this dim
        for a to nBins
            k = b0 + a
            qOld = qVec#[k] + eps
            qNew = qOld + 1
            p = pVec#[k]
            lnPk = pLogVec#[k]
            if kl_mode = 1
                # forward: p*(lnP - ln(qOld/denom)) -> ...(qNew/denom)
                oldT = p * (lnPk - ln(qOld / denom))
                newT = p * (lnPk - ln(qNew / denom))
            elsif kl_mode = 2
                oldT = (qOld / denom) * (ln(qOld / denom) - lnPk)
                newT = (qNew / denom) * (ln(qNew / denom) - lnPk)
            else
                oldF = p * (lnPk - ln(qOld / denom))
                newF = p * (lnPk - ln(qNew / denom))
                oldR = (qOld / denom) * (ln(qOld / denom) - lnPk)
                newR = (qNew / denom) * (ln(qNew / denom) - lnPk)
                oldT = 0.5 * (oldF + oldR)
                newT = 0.5 * (newF + newR)
            endif
            corr_'d'_'a' = newT - oldT
        endfor
    endfor

    # ---- evaluate candidates using only precomputed pieces ----
    bestKL = 1e30
    bestG = 0
    for c to poolSize
        if poolSize = nBGrains
            g = c
        else
            g = randomInteger(1, nBGrains)
        endif
        gbase = (g - 1) * featDim
        ksum = baseSum
        for d to featDim
            a = bBin#[gbase + d]
            ksum = ksum + corr_'d'_'a'
        endfor
        cand = ksum / featDim
        if cand < bestKL
            bestKL = cand
            bestG = g
        endif
    endfor
    if bestG < 1
        bestG = randomInteger(1, nBGrains)
    endif

    # commit chosen grain into Q (increment one bin per dim)
    gbase = (bestG - 1) * featDim
    for d to featDim
        bb = bBin#[gbase + d]
        k = (d - 1) * nBins + bb
        qVec#[k] = qVec#[k] + 1
    endfor
    qTotal = qTotal + 1
    nSel = nSel + 1
    selSnd#[nSel] = bSndArr#[bestG]
    selT0#[nSel] = bT0Arr#[bestG]
    selT1#[nSel] = bT1Arr#[bestG]
    if step mod 50 = 0
        appendInfoLine: "    step ", step, "/", nSteps, "  KL=", fixed$(bestKL, 5)
    endif
endfor

# final KL
for d to featDim
    addBin#[d] = -1
endfor
@klScore: kl_mode
klFinal = klScore.out
appendInfoLine: "  Selected ", nSel, " grains.  KL ",
    ... fixed$(klInitial, 5), " -> ", fixed$(klFinal, 5)

# ========================================================================================
# STAGE 6: SOUND GENERATION (extract selected grains, crossfade OLA, normalise)
# ========================================================================================

appendInfoLine: "[5/5] Rendering output sound..."

xf = crossfade
if xf >= frame_length / 2
    xf = frame_length / 2
endif
advance = frame_length - xf
if advance < frame_length / 4
    advance = frame_length / 4
endif

bufDur = nSel * advance + frame_length + 0.05
bufID = Create Sound from formula: "kl_buf", 1, 0, bufDur, target_sample_rate, "0"

writePtr = 0
for s to nSel
    src = selSnd#[s]
    t0 = selT0#[s]
    t1 = selT1#[s]
    selectObject: src
    sdur = Get total duration
    if t1 > sdur
        t1 = sdur
    endif
    if t0 < 0
        t0 = 0
    endif
    if t1 - t0 >= 0.001
        selectObject: src
        Extract part: t0, t1, "Hanning", 1, "no"
        grainID = selected("Sound")
        glen = Get total duration
        onset = writePtr
        onsetEnd = onset + glen
        if onsetEnd > bufDur
            onsetEnd = bufDur
        endif
        grainStr$ = string$(grainID)
        onsetStr$ = string$(onset)
        selectObject: bufID
        Formula (part): onset, onsetEnd, 1, 1,
            ... "self + Object_" + grainStr$ + "(x - " + onsetStr$ + ")"
        removeObject: grainID
    endif
    writePtr = writePtr + advance
endfor

selectObject: bufID
total = Get total duration
finalDur = output_duration
if finalDur > total
    finalDur = total
endif
Extract part: 0, finalDur, "rectangular", 1, "no"
resultID = selected("Sound")
removeObject: bufID
selectObject: resultID
Scale peak: 0.99
Rename: "KL_Divergence_Corpus_Resynthesis"

# ========================================================================================
# CLEANUP (intermediate objects + kept B sounds)
# ========================================================================================
nocheck removeObject: aFeat
nocheck removeObject: bFeat
nocheck removeObject: bMeta
nocheck removeObject: bSnd
nocheck removeObject: pMat
nocheck removeObject: bBinMat
for k to nBKept
    nocheck removeObject: keptId_'k'
endfor

# ========================================================================================
# STAGE 7: REPORT
# ========================================================================================

if kl_mode = 1
    mode$ = "forward D(P||Q)"
elsif kl_mode = 2
    mode$ = "reverse D(Q||P)"
else
    mode$ = "symmetric"
endif

appendInfoLine: ""
appendInfoLine: "=== REPORT ==="
appendInfoLine: "Corpus A files analysed: ", nAFiles
appendInfoLine: "Corpus B files analysed: ", nBFiles
appendInfoLine: "Corpus B grains available: ", nBGrains
appendInfoLine: "Grains selected: ", nSel
appendInfoLine: "Output duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "Feature dimensions: ", featDim
appendInfoLine: "Histogram bins/feature: ", nBins
appendInfoLine: "KL mode: ", mode$
appendInfoLine: "Initial KL: ", fixed$(klInitial, 6)
appendInfoLine: "Final KL: ", fixed$(klFinal, 6)
appendInfoLine: ""
appendInfoLine: "Result Sound: KL_Divergence_Corpus_Resynthesis (kept open)"

# ========================================================================================
# VISUALIZATION: reference P vs achieved Q for one feature dimension
#   (shows how closely the mosaic's distribution matched the target).
# ========================================================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing distribution match..."

    # choose the dimension to show: the one with the largest P spread
    # (most informative). featDim columns; pick max range of P over bins.
    vizDim = colCEN
    bestSpread = -1
    for d to featDim
        b0 = (d - 1) * nBins
        pmin = 1e30
        pmax = -1e30
        for b to nBins
            pv = pVec#[b0 + b]
            if pv < pmin
                pmin = pv
            endif
            if pv > pmax
                pmax = pv
            endif
        endfor
        if pmax - pmin > bestSpread
            bestSpread = pmax - pmin
            vizDim = d
        endif
    endfor

    # normalise achieved Q for the chosen dim
    b0 = (vizDim - 1) * nBins
    qsum = 0
    for b to nBins
        qsum = qsum + qVec#[b0 + b] + eps
    endfor
    pMax = 0
    for b to nBins
        pv = pVec#[b0 + b]
        qv = (qVec#[b0 + b] + eps) / qsum
        if pv > pMax
            pMax = pv
        endif
        if qv > pMax
            pMax = qv
        endif
    endfor
    if pMax <= 0
        pMax = 1
    endif

    dimName$ = "MFCC c" + string$(vizDim)
    if vizDim = colRMS
        dimName$ = "RMS (loudness)"
    elsif vizDim = colCEN
        dimName$ = "spectral centroid"
    elsif vizDim = colSPR
        dimName$ = "spectral spread"
    endif

    Erase all
    # title band: ONE line (preset folded in), like Bayesian_Drone_Weaver
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Black
    Font size: 13
    Text: 0.5, "centre", 0.5, "half",
        ... "##KL Corpus Resynthesis##  -  " + presetName$ + ",  " + dimName$

    # panel
    Select outer viewport: 0, 8, 0.8, 3.6
    Select inner viewport: 0.9, 7.7, 1.0, 3.4
    Axes: 0, nBins, 0, pMax * 1.1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, nBins, 0, pMax * 1.1
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 5, "yes", "yes", "no"
    Text bottom: "yes", "histogram bin"
    Text left: "yes", "probability"

    # P bars (reference, light blue) ; Q bars (achieved, red, narrower)
    for b to nBins
        pv = pVec#[b0 + b]
        qv = (qVec#[b0 + b] + eps) / qsum
        Paint rectangle: "{0.78, 0.84, 0.95}", b - 0.92, b - 0.08, 0, pv
        Paint rectangle: "{0.75, 0.20, 0.20}", b - 0.66, b - 0.34, 0, qv
    endfor
    Colour: "{0, 0, 0}"
    Draw inner box

    # legend band: ONE row of swatches + labels + stats, all left-aligned
    Select outer viewport: 0, 8, 3.7, 4.3
    Axes: 0, 1, 0, 1
    Font size: 8
    Paint rectangle: "{0.78, 0.84, 0.95}", 0.02, 0.05, 0.40, 0.62
    Text: 0.07, "left", 0.5, "half", "P reference (A)"
    Paint rectangle: "{0.75, 0.20, 0.20}", 0.30, 0.32, 0.40, 0.62
    Text: 0.34, "left", 0.5, "half", "Q output (B)"
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.60, "left", 0.5, "half",
        ... mode$ + "  |  bins " + string$(nBins) +
        ... "  |  KL " + fixed$(klInitial, 3) + " -> " + fixed$(klFinal, 3)
    Black
    appendInfoLine: "  Visualization complete (dimension: ", dimName$, ")."
endif

if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID
