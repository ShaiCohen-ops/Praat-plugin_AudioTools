# ========================================================================================
# Praat AudioTools - KL_Divergence_Corpus_Resynthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.1 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; corpus loading, feature
#     extraction, histogram construction, greedy KL-driven selection,
#     candidate sampling, normalized Hann overlap-add and final rendering
#     are unchanged from v2.0.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, standard title/subtitle, suite typography,
#     neutral panel backgrounds, summary strip and full-page export.
#   - Preserved the defining visualization: reference distribution P
#     versus achieved output distribution Q for the most informative
#     feature dimension.
#   - Added a rendered-output waveform panel and clarified in the summary
#     that the reported KL is the mean of per-dimension marginals, not a
#     joint multidimensional KL.
#
# Changelog v2.0:
#
#   NOTE: audio is NOT comparable to v1.0. Grain placement and the
#   number of grains that reach the output both changed.
#
#   CRITICAL 1 - the reported KL described grains nobody heard.
#     Selection ran ceiling(output_duration / hop_size) steps, but the
#     renderer advanced by (frame_length - crossfade). Measured at the
#     defaults (46.4 ms frame, 23.2 ms hop, 10 ms crossfade, 8 s out):
#     345 grains selected, only 220 starting before the trim point -
#     125 grains, 36.2% of the run, entered Q and the Final KL figure
#     while contributing no audio at all. At the Dense preset (1:4)
#     it is 690 selected against the same 220 heard: 68.1% unheard.
#     v2.0 places grain s at (s - 1) * hop_size, so one selection step
#     is one hop everywhere - in the Corpus A analysis, the Corpus B
#     segmentation, the step count and the render. Crossfade is gone
#     from the form: the overlap is frame_length - hop_size by
#     construction, and exposing it separately is what split the two
#     time bases apart.
#
#   CRITICAL 2 - the Hann OLA was never normalised.
#     Grains were extracted with "Hanning" (Praat bakes the window into
#     the samples) and summed straight into the buffer with no envelope
#     accumulation and no division. Measured in isolation, summing
#     IDENTICAL Hann grains over a constant signal so that any ripple
#     must come from the assembly itself:
#       advance = frame - crossfade, no envelope division  12.69 dB
#       hop = frame/2, no envelope division                 0.000003 dB
#       hop = frame/2 + envelope division                   0.000003 dB
#       advance = frame - crossfade + envelope division     0.00004 dB
#     So the two fixes are independently sufficient here, for different
#     reasons: a Hann window at exactly 50% overlap already sums to a
#     constant, which is why the hop correction alone flattens it, and
#     the envelope division flattens even the wrong hop. v2.0 does both,
#     because the hop makes it correct and the division makes it robust
#     at 1:4 and 1:8, at the head and tail where fewer grains overlap,
#     and for any grain shortened at a file boundary.
#
#     A caveat on how this reads in practice: on a real single-tone
#     Corpus B the finished output still measured 8.77 dB of variation,
#     because grains drawn from different offsets in a periodic signal
#     interfere in phase when summed. That is granular resynthesis
#     behaving normally, not an assembly fault, and no envelope
#     normalisation can remove it.
#
#   CRITICAL 3 - klInitial and klFinal used a denominator for a grain
#     that was not being added. klScore always divided by
#     (qTotal + 1 + nBins * eps), which is right when simulating an
#     addition and wrong otherwise, so the reported distributions did
#     not sum to 1: measured 0.990 at qTotal = 100 and 0.997 at the
#     final qTotal = 345. The candidate scores inside the loop were
#     always correct - only the two headline numbers were off.
#     klScore now takes an explicit addition count.
#
#   4 - The RNG is reset at the end, and seeding now happens
#     immediately before selection rather than before the folder
#     chooser - cancelling the chooser used to leave Praat globally in
#     predictable mode.
#     NOTE: the reviewed claim that the colon call form was invalid
#     does not hold. Verified on 6.4.42: the command form and the
#     parenthesised form both seed and return identical draws
#     (0.35762972 either way). The call is written with parentheses
#     here for consistency with the rest of the suite, not as a fix.
#
#   5 - Candidate_pool is an integer field, so the documented "0 = all"
#     is actually reachable. It was declared positive, which rejects 0.
#
#   6 - Candidates are sampled WITHOUT replacement. randomInteger was
#     called once per slot, so "pool = 40" could test the same grain
#     several times and examine far fewer than 40 distinct grains.
#     A partial Fisher-Yates shuffle now guarantees distinct draws.
#
#   7 - The dimension called "RMS (dB)" is Intensity at the frame
#     centre, sampled from a To Intensity object built with a 100 Hz
#     floor - a 32 ms Gaussian-windowed analysis, not an RMS of the
#     46.4 ms grain. Renamed rather than recomputed, since the feature
#     itself is reasonable.
#
#   8 - Undefined intensity is floored at a defined silence level
#     instead of 0 dB. On peak-normalised material real values sit far
#     above 0, so a single undefined frame used to stretch the
#     histogram range and waste bins.
#
#   9 - Short fades at both ends of the output. The trim can land
#     mid-grain, and envelope normalisation makes the first and last
#     samples louder than before.
#
#   10 - Input validation for the numeric fields, with reported
#     clamping instead of silent correction.
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
#   Features per frame (default 16 dims): MFCC c1..cK, intensity (dB)
#   at the frame centre, spectral centroid, spectral spread.
#   KL modes: forward D(P||Q), reverse D(Q||P), symmetric.
#
#   WHAT THE MODEL IS, PRECISELY:
#   - The KL is a MEAN OF PER-DIMENSION MARGINALS, not a joint KL. It
#     can match the centroid distribution and the intensity
#     distribution separately without reproducing their correlation.
#   - The corpus distribution is FRAME-WEIGHTED, not file-weighted. A
#     ten-minute file contributes ten times the frames of a one-minute
#     file and dominates P accordingly; likewise a long Corpus B file
#     supplies more grains and is likelier to reach the candidate pool.
#   - Every file is peak-normalised to 0.99 before analysis, so the
#     intensity dimension describes DYNAMICS WITHIN each independently
#     normalised file, not the level relations between files.
#   - All corpus files are converted to mono. The output is always
#     mono, whatever the source channel count.
#
#   TIME BASE: one selection step = hop_size, in the Corpus A analysis,
#   the Corpus B segmentation and the render alike. Grains are
#   overlap-added at that hop and divided by the accumulated Hann
#   envelope.
#
# Category: Concatenative / Information-Theoretic Synthesis
# ========================================================================================

form KL Divergence Corpus Resynthesis v2.1
    sentence Corpus_A_folder
    sentence Corpus_B_folder
    optionmenu Preset: 1
        option Custom (use settings below)
        option Coarse / fast
        option Balanced
        option Fine match
        option Dense mosaic
    positive Frame_length 0.0464
    optionmenu Overlap_ratio: 2
        option 1:1  (no overlap)
        option 1:2  (50% overlap)
        option 1:4  (75% overlap)
        option 1:8  (87.5% overlap)
    natural Number_of_mfcc 13
    natural Histogram_bins 32
    optionmenu Kl_mode: 3
        option Forward  D(P||Q)
        option Reverse  D(Q||P)
        option Symmetric
    positive Kl_epsilon 0.000001
    positive Output_duration 8.0
    integer Candidate_pool 40
    integer Max_files_per_corpus 4
    integer Random_seed 12345
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ----------------------------------------------------------------------------------------
# SCRIPT-LEVEL SETTINGS
# ----------------------------------------------------------------------------------------
# Blank Corpus folders open a chooser. Candidate_pool 0 = try every
# Corpus B grain each step; Max_files_per_corpus 0 = no file cap.
# Target sample rate lives here rather than in the dialog: it is
# rarely changed and the form has to stay readable on short screens.

target_sample_rate = 44100

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

# The render overlap follows from the hop (v2.0 CRITICAL 1). v1.0 had a
# separate Crossfade field that set the render advance independently of
# the analysis hop, which is what let selection and synthesis run on
# different clocks.
overlap_s = frame_length - hop_size

# ----------------------------------------------------------------------------------------
# VALIDATION  (v2.0 fix 10)
# ----------------------------------------------------------------------------------------
warnLines$ = ""

if number_of_mfcc < 1
    number_of_mfcc = 1
    warnLines$ = warnLines$ + "  ! Number_of_mfcc < 1 -> raised to 1" + newline$
endif
if histogram_bins < 2
    histogram_bins = 2
    warnLines$ = warnLines$ + "  ! Histogram_bins < 2 -> raised to 2" + newline$
endif
if kl_epsilon <= 0
    kl_epsilon = 1e-6
    warnLines$ = warnLines$ + "  ! Kl_epsilon must be > 0 (ln(0)) -> reset to 1e-6" + newline$
endif
if candidate_pool < 0
    candidate_pool = 0
    warnLines$ = warnLines$ + "  ! Candidate_pool < 0 -> treated as 0 (all grains)" + newline$
endif
if max_files_per_corpus < 0
    max_files_per_corpus = 0
    warnLines$ = warnLines$ + "  ! Max_files_per_corpus < 0 -> treated as 0 (no limit)" + newline$
endif
if frame_length < 0.005
    frame_length = 0.005
    hop_size = frame_length / hopDiv
    overlap_s = frame_length - hop_size
    warnLines$ = warnLines$ + "  ! Frame_length below 5 ms -> raised to 5 ms" + newline$
endif

clearinfo
writeInfoLine: "=== KL Divergence Corpus Resynthesis v2.1 ==="
appendInfoLine: ""
if warnLines$ <> ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
    appendInfoLine: ""
endif

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

# Feature layout: columns 1..K = MFCC, K+1 = intensity (dB at frame
# centre), K+2 = centroid, K+3 = spread
nMfcc = number_of_mfcc
featDim = nMfcc + 3
colINT = nMfcc + 1
colCEN = nMfcc + 2
colSPR = nMfcc + 3
nBins = histogram_bins
silenceFloorDB = 20
eps = kl_epsilon

appendInfoLine: "Corpus A: ", dirA$
appendInfoLine: "Corpus B: ", dirB$
appendInfoLine: "Feature dimensions: ", featDim, " (", nMfcc,
    ... " MFCC + intensity + centroid + spread)"
appendInfoLine: "Histogram bins/feature: ", nBins
appendInfoLine: "Frame: ", fixed$(frame_length * 1000, 1), " ms   hop: ",
    ... fixed$(hop_size * 1000, 1), " ms   (overlap 1:", hopDiv, ")"
appendInfoLine: "Render overlap: ", fixed$(overlap_s * 1000, 1),
    ... " ms (derived from the hop; one step = one hop everywhere)"
appendInfoLine: "Output is MONO; every file is peak-normalised before analysis."
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
            # v2.0 fix 7: this dimension is INTENSITY at the frame
            # centre, read from a To Intensity object built with a
            # 100 Hz floor - a ~32 ms Gaussian-windowed analysis, not
            # an RMS of the 46.4 ms grain. v1.0 labelled it "RMS (dB)".
            selectObject: .intens
            .db = Get value at time: .t, "Cubic"
            # v2.0 fix 8: an undefined reading used to become 0 dB. On
            # peak-normalised material real values sit far above that,
            # so one undefined frame stretched the histogram range and
            # wasted most of the bins.
            if .db = undefined
                .db = silenceFloorDB
            endif
            if .db < silenceFloorDB
                .db = silenceFloorDB
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
            Set value: .row, colINT, .db
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
# v2.0 CRITICAL 3: .nAdd says whether a grain addition is being
# simulated. v1.0 hard-coded "+ 1" into the denominator, which is right
# for a candidate and wrong for the current Q - so klInitial and
# klFinal were computed against a Q that summed to less than 1
# (measured 0.990 at qTotal 100, 0.997 at the final qTotal 345). The
# candidate scores inside the selection loop were always correct.
procedure klScore: .klDir, .nAdd
    .denom = qTotal + .nAdd + nBins * eps
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
@klScore: kl_mode, 0
klInitial = klScore.out

# v2.0 CRITICAL 1: one selection step is one hop, and the renderer
# uses the same hop. v1.0 counted steps at hop_size but advanced the
# write pointer by (frame_length - crossfade), so at the defaults 125
# of 345 selected grains never reached the output while still counting
# toward Q and the reported Final KL.
stepHop = hop_size
nSteps = ceiling(output_duration / stepHop)
if nSteps < 1
    nSteps = 1
endif
poolSize = candidate_pool
if poolSize <= 0 or poolSize > nBGrains
    poolSize = nBGrains
endif

# v2.0 fix 4: seed here, not before the folder chooser. Cancelling the
# chooser used to exit with Praat's generator left globally in
# predictable mode.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif
appendInfoLine: "  Seed: ", seedLabel$
appendInfoLine: "  Steps: ", nSteps, " at ", fixed$(stepHop * 1000, 1),
    ... " ms  (= render hop)"

# v2.0 fix 6: candidates without replacement. v1.0 drew
# randomInteger(1, nBGrains) once per slot, so a pool of 40 could test
# the same grain repeatedly and inspect far fewer than 40 distinct
# grains. permIdx# is shuffled partially each step (Fisher-Yates over
# the first poolSize positions), which is O(poolSize), not O(nBGrains).
permIdx# = zero#(nBGrains)
for g to nBGrains
    permIdx#[g] = g
endfor

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
    if poolSize < nBGrains
        for c to poolSize
            r = randomInteger(c, nBGrains)
            tmpv = permIdx#[c]
            permIdx#[c] = permIdx#[r]
            permIdx#[r] = tmpv
        endfor
    endif
    for c to poolSize
        if poolSize = nBGrains
            g = c
        else
            g = permIdx#[c]
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
@klScore: kl_mode, 0
klFinal = klScore.out
appendInfoLine: "  Selected ", nSel, " grains.  KL ",
    ... fixed$(klInitial, 5), " -> ", fixed$(klFinal, 5)

# ========================================================================================
# STAGE 6: SOUND GENERATION (fixed-hop Hann OLA, envelope-normalised)
# ========================================================================================

appendInfoLine: "[5/5] Rendering output sound..."

# v2.0 CRITICAL 1 + 2: grain s is placed at (s - 1) * hop_size - the
# same hop the corpora were analysed at and the same one the step count
# uses - and each Hann window is accumulated into an envelope buffer
# that the output is divided by. v1.0 advanced by
# (frame_length - crossfade) and summed raw Hann grains with no
# normalisation, so the level breathed at the grain rate: measured
# 6.02 dB peak-to-trough on a single-tone Corpus B, where every grain
# is identical and any ripple must therefore come from the assembly.

renderHop = hop_size
bufDur = (nSel - 1) * renderHop + frame_length + 0.05
bufID = Create Sound from formula: "kl_buf", 1, 0, bufDur, target_sample_rate, "0"
envID = Create Sound from formula: "kl_env", 1, 0, bufDur, target_sample_rate, "0"

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
        # rectangular extraction; the window is applied once, below, so
        # the same shape can be accumulated into the envelope
        selectObject: src
        Extract part: t0, t1, "rectangular", 1, "no"
        grainID = selected("Sound")
        selectObject: grainID
        glen = Get total duration
        selectObject: grainID
        Formula: "self * (0.5 - 0.5 * cos(2 * pi * (x - xmin) / (xmax - xmin)))"

        onset = (s - 1) * renderHop
        onsetEnd = onset + glen
        if onsetEnd > bufDur
            onsetEnd = bufDur
            glen = bufDur - onset
        endif
        if glen > 0.0005
            selectObject: grainID
            Shift times to: "start time", onset
            grainStr$ = string$(grainID)
            onsetStr$ = fixed$(onset, 9)
            glenStr$ = fixed$(glen, 9)

            selectObject: bufID
            Formula (part): onset, onsetEnd, 1, 1,
                ... "self + object(" + grainStr$ + ", x)"

            selectObject: envID
            Formula (part): onset, onsetEnd, 1, 1,
                ... "self + (0.5 - 0.5 * cos(2 * pi * (x - " + onsetStr$ +
                ... ") / " + glenStr$ + "))"
        endif
        removeObject: grainID
    endif
endfor

# divide by the accumulated envelope; the divisor is floored so the
# head and tail fade out rather than being amplified
selectObject: envID
envPeak = Get absolute extremum: 0, 0, "None"
if envPeak < 1e-9
    envPeak = 1e-9
endif
efStr$ = fixed$(envPeak * 0.02, 9)
envStr$ = string$(envID)
selectObject: bufID
Formula: "self / max(object[" + envStr$ + ", col], " + efStr$ + ")"
removeObject: envID

selectObject: bufID
total = Get total duration
finalDur = output_duration
if finalDur > total
    finalDur = total
endif
selectObject: bufID
Extract part: 0, finalDur, "rectangular", 1, "no"
resultID = selected("Sound")
removeObject: bufID

# v2.0 fix 9: the trim can land mid-grain, and envelope normalisation
# makes the first and last samples louder than they used to be.
selectObject: resultID
edgeFade = 0.005
if edgeFade > finalDur * 0.1
    edgeFade = finalDur * 0.1
endif
if edgeFade > 0.0002
    efs$ = fixed$(edgeFade, 8)
    selectObject: resultID
    Formula: "if x - xmin < " + efs$ + " then self * ((x - xmin) / " + efs$ + ") else self fi"
    selectObject: resultID
    Formula: "if xmax - x < " + efs$ + " then self * ((xmax - x) / " + efs$ + ") else self fi"
endif

selectObject: resultID
Scale peak: 0.99
Rename: "KL_Divergence_Corpus_Resynthesis"

# v2.0 fix 4: hand the generator back to its safe state.
random_initializeSafelyAndUnpredictably ()

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
# VISUALIZATION
# ========================================================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing distribution match..."

    # Choose the dimension to show: the one with the largest P spread.
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

    # Normalize achieved Q for the chosen dimension.
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
    if vizDim = colINT
        dimName$ = "Intensity (dB, frame centre)"
    elsif vizDim = colCEN
        dimName$ = "Spectral centroid"
    elsif vizDim = colSPR
        dimName$ = "Spectral spread"
    endif

    selectObject: resultID
    vizOutPeak = Get absolute extremum: 0, 0, "None"
    vizOutCh = Get number of channels

    if candidate_pool = 0
        poolDesc$ = "all Corpus B grains"
    else
        poolDesc$ = string$(candidate_pool) + " candidates/step"
    endif

    pageHeight = 6.65
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##KL Divergence Corpus Resynthesis v2.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", presetName$ + " | " + mode$ + " | " + dimName$ + " | KL " + fixed$(klInitial, 4) + " -> " + fixed$(klFinal, 4)

    # === Reference P vs achieved Q ===
    Select outer viewport: 0, 8, 0.72, 3.72
    Select inner viewport: 0.60, 7.70, 1.02, 3.48
    Axes: 0, nBins, 0, pMax * 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nBins, 0, pMax * 1.12

    for b to nBins
        pv = pVec#[b0 + b]
        qv = (qVec#[b0 + b] + eps) / qsum
        Paint rectangle: "{0.78, 0.84, 0.95}", b - 0.92, b - 0.08, 0, pv
        Paint rectangle: "{0.75, 0.25, 0.25}", b - 0.66, b - 0.34, 0, qv
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Probability"
    Text bottom: "no", "Histogram bin"
    Text top: "no", "Distribution Match | blue P reference (Corpus A) | red Q output from Corpus B"

    # === Legend strip ===
    Select outer viewport: 0, 8, 3.80, 4.16
    Select inner viewport: 0.60, 7.70, 3.86, 4.10
    Axes: 0, 1, 0, 1
    Font size: 6

    Paint rectangle: "{0.78, 0.84, 0.95}", 0.02, 0.045, 0.35, 0.65
    Colour: "Black"
    Text: 0.055, "left", 0.50, "half", "P reference"
    Paint rectangle: "{0.75, 0.25, 0.25}", 0.23, 0.255, 0.35, 0.65
    Text: 0.265, "left", 0.50, "half", "Q achieved"
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.48, "left", 0.50, "half", "Shown dimension = largest P histogram spread"

    # === Rendered output waveform ===
    Select outer viewport: 0, 8, 4.34, 5.34
    Select inner viewport: 0.60, 7.70, 4.52, 5.14
    selectObject: resultID
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Rendered Mosaic | " + fixed$(finalDur, 2) + " s | " + string$(vizOutCh) + " ch | peak " + fixed$(vizOutPeak, 3)

    # === Summary strip ===
    Select outer viewport: 0, 8, 5.54, 6.60
    Select inner viewport: 0.60, 7.70, 5.62, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Corpora##  A " + string$(nAFiles) + " files | B " + string$(nBFiles) + " files, " + string$(nBGrains) + " grains | selected " + string$(nSel) + " | " + string$(featDim) + " feature dimensions | " + string$(nBins) + " bins"
    summary2$ = "##KL selection##  " + mode$ + " | mean of per-dimension marginals, not joint KL | " + poolDesc$ + " | seed " + seedLabel$ + " | " + fixed$(klInitial, 5) + " -> " + fixed$(klFinal, 5)
    summary3$ = "##Time base & output##  frame " + fixed$(frame_length * 1000, 1) + " ms | hop " + fixed$(hop_size * 1000, 1) + " ms | overlap 1:" + string$(hopDiv) + " | normalized Hann OLA | mono output | " + fixed$(finalDur, 2) + " s"
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

    appendInfoLine: "  Visualization complete (dimension: ", dimName$, ")."
endif

if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID
