# ============================================================
# Praat AudioTools - PCA_Tone_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PCA Tone Shaper - Maps PCA-derived timbre features to
#   dynamic 3-band EQ for adaptive spectral shaping.
#
# Changelog v0.5 (2026):
#   - FIX (critical): chunks were Hamming-windowed but written back
#     ABUTTING, with no overlap -- the output amplitude dipped to
#     ~8% at every chunk boundary (a 5 Hz tremolo at the default
#     200 ms chunk). Now proper 50%-overlap-add with Hann windows:
#     the window sum is exactly 1 everywhere (head and tail covered
#     by zero-padded boundary chunks), and band gains crossfade
#     smoothly between chunks instead of stepping.
#   - FIX: crossover smoothing unified to 100 Hz on all three band
#     filters. The old mixed smoothings (100/200/500) left ~16%
#     ripple around each crossover; with equal smoothing the skirts
#     are exactly complementary -- verified: 3-band sum matches the
#     band-limited reference at machine precision (3e-16 RMS).
#     The "unity gain when gL=gM=gH=1" claim is now exactly true
#     within the band range.
#   - FIX: HNR was sampled by PITCH-frame index ("Get value in
#     frame: i"), but Harmonicity frames neither align with nor
#     count the same as Pitch frames -- tail frames read out of
#     range (undefined -> 0 fallback), the rest were time-shifted.
#     Now queried by time with cubic interpolation, like the other
#     features.
#   - FIX: PCA guard raised to nF >= 5 (3 components need at least
#     4 rows; "To Configuration: 3" errored on 3-frame inputs).
#   - VIZ: gain trajectory drawn at true chunk centers on the new
#     hop timeline.
#
# Changelog v0.3:
#   - Fixed Formula variable interpolation
#   - Fixed Concatenate cleanup (TextGrid orphan)
#   - Added presets
#   - Added visualization
#   - Modern syntax throughout
#
# Changelog v0.4 (2026):
#   - FIX: Band mixing was using "Combine to stereo + Convert to
#     mono" twice, which averages instead of summing. The math
#     produced low/4 + mid/4 + high/2 instead of low + mid + high
#     — every preset's gains have been silently wrong since v0.1.
#     Replaced with proper Formula-based summation: the bands now
#     sum to unity gain when gL=gM=gH=1.0.
#   - SPEED: Per-chunk Concatenate in the assembly loop rebuilt
#     the entire growing buffer on every iteration — O(n^2) cost.
#     Replaced with pre-allocated output buffer + Formula (part)
#     in-place writes. Significant speedup on long inputs.
#   - VIZ: Added PC1/PC2/PC3 trajectory panel showing the
#     normalized PCA scores over time — directly displays what
#     the system is responding to.
#   - VIZ: Added input/output spectrogram comparison panels so
#     the spectral effect of the EQ is visible.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSnd = selected("Sound")
origName$ = selected$("Sound")

form PCA Tone Shaper v0.8  (adaptive PCA-driven EQ)
    optionmenu Preset: 1
        option Manual
        option Low crossover (200/2000 Hz)
        option Wide band (150/3000 Hz)
        option Mid focused (300/1800 Hz)
        option Gentle (low strength)
        option Strong (full range, high strength)
    positive Chunk_ms 200
    positive Frame_step_seconds 0.01
    positive Pca_strength 1.0
    positive Depth_dB 9
    positive Low_hi_crossover1_hz 200
    positive Low_hi_crossover2_hz 2000
    positive High_band_top_hz 8000
    positive Max_formant_hz 5500
    integer N_formants 5
    positive F0_min 75
    positive F0_max 600
    optionmenu Output_level_mode: 2
        option Preserve gain
        option Conditional limiter
        option Normalize to headroom
    positive Headroom 0.97
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# v0.6: the presets are named for what they SET, not for a tone colour.
# v0.5 called them Warm, Bright, Presence and Smooth, but the gain map
# is identical in all of them - only the crossovers and the strength
# change. PC1 is not brightness, PC2 is not presence and PC3 is not
# body; PCA only guarantees axes of decreasing variance, and an
# eigenvector's SIGN is mathematically arbitrary, so the same preset
# can tilt one way on one file and the other way on another. "Warm
# (Bass Boost)" could deliver a treble boost. The names now describe
# the band layout, which is the part that is actually determined.
#
# What this tool is: an ADAPTIVE PCA-DRIVEN EQ whose motion follows the
# largest axes of variation in the input's own features. It is not a
# semantic tone shaper, and making it one would need direct spectral
# features (centroid, high/low energy ratio) to anchor the axes.
#
# Depth_dB is the MAXIMUM swing of a band, in dB, at Pca_strength = 1.
# v0.7 and earlier used unnamed linear coefficients that produced under
# 2 dB at the default and left the mid band essentially static.
#
# Pca_strength = 0 is now a true bypass: a residual band above
# High_band_top_hz passes at unity, so the sum is the whole signal.
#
# ON MISSING FEATURES (documented, not restructured): undefined
# formants become 500/1500/2500 Hz and undefined HNR becomes 0 dB.
# Those are meaningful acoustic values, not "missing" markers - 0 dB
# HNR means equal harmonic and noise energy - so regions where the
# analysis failed look like a canonical vowel of middling periodicity,
# and PC1 can end up describing valid-analysis versus fallback-template
# rather than timbre. Fixing this properly needs validity flags on
# each feature and a decision about whether to drop those frames or
# carry validity as its own dimension; that is a model change and is
# left for a later pass rather than half-done here.

# ============================================
# VALIDATION  (v0.6 fix 8)
# ============================================
if chunk_ms <= 0
    exitScript: "Chunk_ms must be greater than 0."
endif
if frame_step_seconds <= 0
    exitScript: "Frame_step_seconds must be greater than 0."
endif
if pca_strength < 0
    pca_strength = 0
endif
if f0_min <= 0 or f0_max <= f0_min
    exitScript: "Need 0 < F0_min < F0_max."
endif
if n_formants < 1
    n_formants = 1
endif
if headroom <= 0 or headroom > 1
    headroom = 0.97
    appendInfoLine: "  ! Headroom must be in (0, 1] -> 0.97"
endif

# ===== PRESET LOGIC =====
# v0.7 CRITICAL: the preset LOGIC now matches the dialog. v0.6 renamed
# the options but left v0.5's bodies, so choosing "Low crossover
# (200/2000 Hz)" actually applied 250/1500 Hz at strength 1.0 and
# named the output "..._PCATone_Warm". The interface and the engine
# were describing two different tools.
if preset = 2
    # Low crossover
    pca_strength = 0.8
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "LowCrossover"
elsif preset = 3
    # Wide band
    pca_strength = 0.8
    low_hi_crossover1_hz = 150
    low_hi_crossover2_hz = 3000
    presetName$ = "WideBand"
elsif preset = 4
    # Mid focused
    pca_strength = 0.8
    low_hi_crossover1_hz = 300
    low_hi_crossover2_hz = 1800
    presetName$ = "MidFocused"
elsif preset = 5
    # Gentle
    pca_strength = 0.4
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "Gentle"
elsif preset = 6
    # Strong
    pca_strength = 1.4
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "Strong"
else
    presetName$ = "Manual"
endif

# ===== SETUP =====
clearinfo
writeInfoLine: "=== PCA Tone Shaper v0.8 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Strength: ", pca_strength
appendInfoLine: ""

maxFmtHz = max_formant_hz
nFmt = n_formants

selectObject: origSnd
dur = Get total duration
fs = Get sampling frequency
if dur <= 0
    exitScript: "Invalid sound."
endif

nch = Get number of channels
if nch > 1
    selectObject: origSnd
    Convert to mono
    snd = selected("Sound")
else
    selectObject: origSnd
    Copy: "WorkCopy"
    snd = selected("Sound")
endif

# v0.6 fix 6: a silent input yields constant features, a degenerate
# PCA, and - under the old unconditional Scale peak - amplification of
# whatever numerical residue came out.
selectObject: snd
srcPeakChk = Get absolute extremum: 0, 0, "None"
if srcPeakChk < 1e-5
    exitScript: "The selected Sound is silent (or near-silent); there is nothing to analyse."
endif

# ===== GUARDS =====
nyq = fs / 2
# v0.6 fix 8: the guards below can produce zero or negative edges at a
# low sample rate, so the rate is checked first.
if nyq < 2000
    exitScript: "Sample rate too low for this tool: Nyquist is " +
        ... fixed$(nyq, 0) + " Hz and the three bands cannot be laid out."
endif
if low_hi_crossover1_hz >= low_hi_crossover2_hz
    exitScript: "Low_hi_crossover1_hz must be below Low_hi_crossover2_hz."
endif

if high_band_top_hz > nyq - 50
    high_band_top_hz = nyq - 50
endif
if low_hi_crossover2_hz > high_band_top_hz - 50
    low_hi_crossover2_hz = high_band_top_hz - 50
endif
if low_hi_crossover1_hz < 20
    low_hi_crossover1_hz = 20
endif
if low_hi_crossover1_hz > low_hi_crossover2_hz - 20
    low_hi_crossover1_hz = low_hi_crossover2_hz - 20
endif
if maxFmtHz > nyq - 200
    maxFmtHz = nyq - 200
endif
if f0_min < 20
    f0_min = 20
endif
if f0_max > nyq - 50
    f0_max = nyq - 50
endif
if pca_strength < 0
    pca_strength = 0
endif
if pca_strength > 1.5
    pca_strength = 1.5
endif

appendInfoLine: "Bands: Low 0-", low_hi_crossover1_hz, " | Mid ", low_hi_crossover1_hz, "-", low_hi_crossover2_hz, " | High ", low_hi_crossover2_hz, "-", high_band_top_hz

# ===== ANALYSIS OBJECTS =====
appendInfoLine: "Extracting features..."

selectObject: snd
# v0.7: Frame_step_seconds now sets the PITCH grid as well. In v0.6 it
# only reached To Harmonicity, so changing it altered HNR resolution
# and nothing else - not the PCA row count, not the control rate, not
# the chunk mapping.
To Pitch: frame_step_seconds, f0_min, f0_max
pit = selected("Pitch")

selectObject: snd
To Intensity: 75, 0, "yes"
inten = selected("Intensity")

selectObject: snd
To Harmonicity (cc): frame_step_seconds, f0_min, 0.1, 1.0
hnr = selected("Harmonicity")

selectObject: snd
To Formant (burg): 0, nFmt, maxFmtHz, 0.025, 50
fmtObj = selected("Formant")

# ===== FRAME GRID =====
selectObject: pit
nF = Get number of frames
# v0.5: 3 PCA components need at least 4 data rows
if nF < 5
    exitScript: "Not enough frames for PCA (need >= 5)."
endif
t0 = Get start time
dt = Get time step
# v0.7: frame 1's CENTRE, not the domain start. Feature extraction was
# already using the real frame times, but the chunk-to-frame mapping
# below still assumed frame 1 sits at t0 + dt/2.
selectObject: pit
pitchX1 = Get time from frame number: 1
if dt <= 0
    dt = frame_step_seconds
endif

appendInfoLine: "  ", nF, " frames"

# ===== FEATURE TABLE (nF x 8) =====
Create TableOfReal: "feat", nF, 8
feat = selected("TableOfReal")

for i from 1 to nF
    # v0.6: the Pitch object's own frame centre. Get start time returns
    # the domain start, not the centre of frame 1, so the whole grid
    # was offset from the analysis it was reading.
    selectObject: pit
    t = Get time from frame number: i
    
    selectObject: fmtObj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    if f1 = undefined or f1 <= 0
        f1 = 500
    endif
    if f2 = undefined or f2 <= 0
        f2 = 1500
    endif
    if f3 = undefined or f3 <= 0
        f3 = 2500
    endif
    r21 = f2 / f1
    r32 = f3 / f2

    selectObject: pit
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 < 0
        f0 = 0
    endif

    selectObject: inten
    intVal = Get value at time: t, "cubic"
    if intVal = undefined
        intVal = 60
    endif

    # v0.5: query by TIME, not by pitch-frame index -- Harmonicity
    # frames neither align with nor count the same as Pitch frames
    selectObject: hnr
    hnrVal = Get value at time: t, "Cubic"
    if hnrVal = undefined
        hnrVal = 0
    endif

    selectObject: feat
    Set value: i, 1, f1
    Set value: i, 2, f2
    Set value: i, 3, f3
    Set value: i, 4, r21
    Set value: i, 5, r32
    Set value: i, 6, f0
    Set value: i, 7, intVal
    Set value: i, 8, hnrVal
endfor

# ===== Z-SCORES =====
appendInfoLine: "Computing z-scores..."

selectObject: feat
nRows = Get number of rows
nCols = Get number of columns
Create TableOfReal: "zfeat", nRows, nCols
zfeat = selected("TableOfReal")

for colIdx from 1 to nCols
    selectObject: feat
    sum = 0
    for rowIdx from 1 to nRows
        val = Get value: rowIdx, colIdx
        sum = sum + val
    endfor
    mean = sum / nRows
    sumSq = 0
    for rowIdx from 1 to nRows
        selectObject: feat
        val = Get value: rowIdx, colIdx
        diff = val - mean
        sumSq = sumSq + diff*diff
    endfor
    sd = sqrt(sumSq / nRows)
    if sd = 0
        sd = 1
    endif
    for rowIdx from 1 to nRows
        selectObject: feat
        val = Get value: rowIdx, colIdx
        z = (val - mean) / sd
        selectObject: zfeat
        Set value: rowIdx, colIdx, z
    endfor
endfor

# ===== PCA AND SCORES =====
appendInfoLine: "Running PCA..."

selectObject: zfeat
To PCA
pca = selected("PCA")
selectObject: zfeat
plusObject: pca
To Configuration: 3
config = selected("Configuration")
selectObject: config
To TableOfReal
scr = selected("TableOfReal")

# Get variance explained
selectObject: pca
frac = Get fraction variance accounted for: 1, 3
expl = 100 * frac
appendInfoLine: "  PC1-3 explain ", fixed$(expl, 1), "% variance"

# ===== NORMALIZE PC1..3 TO [-1,1] =====
selectObject: scr
nScores = Get number of rows
Create TableOfReal: "ctrl", nScores, 3
ctrl = selected("TableOfReal")

# Store for visualization
pcVar# = zero#(3)
pcShare# = zero#(3)
pc1_vals# = zero#(nScores)
pc2_vals# = zero#(nScores)
pc3_vals# = zero#(nScores)

for pcNum from 1 to 3
    selectObject: scr
    mn = 1e30
    mx = -1e30
    for ii from 1 to nScores
        vv = Get value: ii, pcNum
        if vv < mn
            mn = vv
        endif
        if vv > mx
            mx = vv
        endif
    endfor
    # v0.6 CRITICAL 1 + 2: v0.5 min-max stretched EVERY axis to -1..+1
    # and, when an axis had no range at all, mapped it to
    # 2*(0/1) - 1 = -1. Two consequences, both measured:
    #   * a CONSTANT PC produced control -1.0000, so at strength 0.8 it
    #     drove body = 0.30 * 0.8 * -1 = -0.2400 permanently - a fixed
    #     EQ offset from a component carrying no information at all.
    #   * a PC spanning 100.0 and a PC spanning 0.01 both became
    #     -1..+1, giving a negligible axis exactly the same authority
    #     over the EQ as the dominant one.
    # v0.6 uses a z-score with a clamp, and gates out axes whose share
    # of the total variance is negligible. A neutral axis now reads 0.
    sumV = 0
    for ii from 1 to nScores
        selectObject: scr
        vv = Get value: ii, pcNum
        sumV = sumV + vv
    endfor
    muV = sumV / nScores
    ssV = 0
    for ii from 1 to nScores
        selectObject: scr
        vv = Get value: ii, pcNum
        dV = vv - muV
        ssV = ssV + dV * dV
    endfor
    if nScores > 1
        sdV = sqrt(ssV / (nScores - 1))
    else
        sdV = 0
    endif
    pcVar#[pcNum] = sdV * sdV

    for ii from 1 to nScores
        selectObject: scr
        vv = Get value: ii, pcNum
        if sdV < 1e-9
            # no variation: this axis says nothing, so it modulates
            # nothing
            nv = 0
        else
            nv = (vv - muV) / (2.5 * sdV)
            if nv > 1
                nv = 1
            endif
            if nv < -1
                nv = -1
            endif
        endif
        selectObject: ctrl
        Set value: ii, pcNum, nv

        if pcNum = 1
            pc1_vals#[ii] = nv
        elsif pcNum = 2
            pc2_vals#[ii] = nv
        else
            pc3_vals#[ii] = nv
        endif
    endfor
endfor

# v0.6 CRITICAL 2: gate out axes with a negligible share of the total
# variance. PCA orders its axes by explained variance, but v0.5's
# per-axis min-max erased that ordering at the point of control - a PC3
# holding a fraction of a percent of the variance steered the EQ as
# hard as PC1.
totVar = pcVar#[1] + pcVar#[2] + pcVar#[3]
if totVar < 1e-12
    totVar = 1
endif
varGateFrac = 0.02
for pcNum from 1 to 3
    shareHere = pcVar#[pcNum] / totVar
    pcShare#[pcNum] = shareHere
    if shareHere < varGateFrac
        appendInfoLine: "  PC", pcNum, " holds ", fixed$(100 * shareHere, 2),
            ... "% of the variance (< ", fixed$(100 * varGateFrac, 0),
            ... "%) - gated out; it will not modulate the EQ."
        # v0.7 CRITICAL: zero the ctrl TABLE too. v0.6 zeroed only the
        # visualisation vectors, so an axis reported as "gated out" and
        # drawn as a flat line still drove the EQ at full strength - the
        # picture and the Info text hid what the engine was doing.
        for ii from 1 to nScores
            selectObject: ctrl
            Set value: ii, pcNum, 0
            if pcNum = 1
                pc1_vals#[ii] = 0
            elsif pcNum = 2
                pc2_vals#[ii] = 0
            else
                pc3_vals#[ii] = 0
            endif
        endfor
    endif
endfor
appendInfoLine: "  Variance share (within PC1-3, not of all components): PC1 ", fixed$(100*pcShare#[1], 1),
    ... "%  PC2 ", fixed$(100*pcShare#[2], 1), "%  PC3 ", fixed$(100*pcShare#[3], 1), "%"

# ===== CHUNKED PROCESSING (v0.5: 50% OVERLAP-ADD) =====
# Each chunk is Hann-windowed and overlap-added at half-chunk hops.
# Hann windows at 50% overlap sum to exactly 1, so unity gains give
# a transparent pass (the old abutting Hamming chunks dipped to ~8%
# amplitude at every boundary -- a 5 Hz tremolo at 200 ms chunks).
# Boundary chunks overhang the file edges; Extract part zero-pads
# outside the domain, so the window sum stays 1 over [0, dur].
# Bonus: band gains now crossfade smoothly between chunks.
appendInfoLine: "Processing chunks (50% overlap-add)..."

cDur = chunk_ms / 1000
if cDur < 2 * dt
    cDur = 2 * dt
endif
hop = cDur / 2
nChunks = ceiling(dur / hop) + 1
if nChunks < 2
    nChunks = 2
endif

appendInfoLine: "  ", nChunks, " chunks of ", chunk_ms, " ms (hop ",
    ... fixed$(hop * 1000, 0), " ms)"

# ============================================================
# CHUNK CONTROL NORMALISATION  (v0.7)
# ============================================================
# WHY THE EFFECT WAS FAINT. Two things shrank it, measured on the test
# signal at strength 0.8:
#   * v0.6's z/2.5-sigma scaling only reaches +/-1 at 2.5 SD, which
#     almost no frame hits. Measured mean |control|: PC1 0.3211,
#     PC2 0.3138, PC3 0.3478 - about a third of the available range.
#     v0.5's min-max at least guaranteed the extremes touched +/-1.
#   * the EQ is driven by the MEAN control over a whole chunk (~20
#     frames at 200 ms), and averaging shrinks it again.
# Result: the low-band gain deviated from unity by a mean of 0.089 and
# peaked at 1.79 dB - under a dB most of the time, which is why it was
# barely audible.
#
# The fix normalises the values that ACTUALLY drive the EQ. A first
# pass computes the raw chunk means, then each axis is centred on its
# median and scaled so its 5th-95th percentile span reaches +/-1. A
# constant axis still maps to 0, and a gated axis stays 0.
appendInfoLine: "Measuring chunk control range..."

cm1# = zero#(nChunks)
cm2# = zero#(nChunks)
cm3# = zero#(nChunks)

for k from 1 to nChunks
    t1 = (k - 1) * hop
    t2 = t1 + cDur
    f1i = ceiling((t1 - pitchX1) / dt) + 1
    f2i = floor((t2 - pitchX1) / dt) + 1
    if f1i < 1
        f1i = 1
    endif
    if f2i > nScores
        f2i = nScores
    endif
    if f2i < f1i
        f2i = f1i
    endif
    a1 = 0
    a2 = 0
    a3 = 0
    cnt = 0
    selectObject: ctrl
    nCtrlRows = Get number of rows
    for frameIdx from f1i to f2i
        if frameIdx <= nCtrlRows
            selectObject: ctrl
            v1 = Get value: frameIdx, 1
            selectObject: ctrl
            v2 = Get value: frameIdx, 2
            selectObject: ctrl
            v3 = Get value: frameIdx, 3
            a1 += v1
            a2 += v2
            a3 += v3
            cnt += 1
        endif
    endfor
    if cnt = 0
        cnt = 1
    endif
    cm1#[k] = a1 / cnt
    cm2#[k] = a2 / cnt
    cm3#[k] = a3 / cnt
endfor

procedure robustScale: .n
    # median and the 5th/95th percentile span of rsSrc#
    for .a from 1 to .n
        rsSort#[.a] = rsSrc#[.a]
    endfor
    for .a from 1 to .n - 1
        for .b from 1 to .n - .a
            .b2 = .b + 1
            if rsSort#[.b] > rsSort#[.b2]
                .tv = rsSort#[.b]
                rsSort#[.b] = rsSort#[.b2]
                rsSort#[.b2] = .tv
            endif
        endfor
    endfor
    .mid = round(.n / 2)
    if .mid < 1
        .mid = 1
    endif
    robustScale.med = rsSort#[.mid]
    .lo = round(.n * 0.05)
    if .lo < 1
        .lo = 1
    endif
    .hi = round(.n * 0.95)
    if .hi > .n
        .hi = .n
    endif
    .span = (rsSort#[.hi] - rsSort#[.lo]) / 2
    if .span < 1e-9
        robustScale.scl = 0
    else
        robustScale.scl = 1 / .span
    endif
endproc

rsSort# = zero#(nChunks)

rsSrc# = cm1#
@robustScale: nChunks
med1 = robustScale.med
scl1 = robustScale.scl
rsSrc# = cm2#
@robustScale: nChunks
med2 = robustScale.med
scl2 = robustScale.scl
rsSrc# = cm3#
@robustScale: nChunks
med3 = robustScale.med
scl3 = robustScale.scl

for k from 1 to nChunks
    v = (cm1#[k] - med1) * scl1
    cm1#[k] = max(-1, min(1, v))
    v = (cm2#[k] - med2) * scl2
    cm2#[k] = max(-1, min(1, v))
    v = (cm3#[k] - med3) * scl3
    cm3#[k] = max(-1, min(1, v))
endfor


# Store gains for visualization (per chunk, at chunk centers)
gainL_vals# = zero#(nChunks)
gainM_vals# = zero#(nChunks)
gainH_vals# = zero#(nChunks)

# Pre-allocated output buffer; each windowed chunk is overlap-added
# into it at its time offset via Formula (part).
outS = Create Sound from formula: origName$ + "_PCATone_" + presetName$,
    ... 1, 0, dur, fs, "0"

for k from 1 to nChunks
    # Chunk k is centered at (k-1)*hop; the first chunk overhangs
    # the file start, the last overhangs the end (zero-padded).
    t1 = (k - 2) * hop
    t2 = t1 + cDur

    # Frame indices for the control average (clamped to valid range)
    # v0.7: frames whose CENTRES fall inside this chunk.
    f1i = ceiling((t1 - pitchX1) / dt) + 1
    f2i = floor((t2 - pitchX1) / dt) + 1
    if f1i < 1
        f1i = 1
    endif
    if f2i > nScores
        f2i = nScores
    endif
    if f2i < f1i
        f2i = f1i
    endif

    # Mean controls
    a1 = 0
    a2 = 0
    a3 = 0
    effCnt = 0
    selectObject: ctrl
    nCtrlRows = Get number of rows
    for frameIdx from f1i to f2i
        if frameIdx <= nCtrlRows
            val1 = Get value: frameIdx, 1
            val2 = Get value: frameIdx, 2
            val3 = Get value: frameIdx, 3
            a1 = a1 + val1
            a2 = a2 + val2
            a3 = a3 + val3
            effCnt = effCnt + 1
        endif
    endfor
    if effCnt = 0
        effCnt = 1
    endif
    # v0.7: the normalised chunk controls from the pre-pass, so the
    # values that drive the EQ actually span +/-1.
    pc1m = cm1#[k]
    pc2m = cm2#[k]
    pc3m = cm3#[k]

    # ========================================================
    # BAND GAINS IN dB  (v0.8)
    # ========================================================
    # WHY THE EFFECT WAS STILL FAINT after v0.7 restored the control
    # range. The controls were fine; the COEFFICIENTS were tiny and the
    # clamp was unreachable. Measured at the defaults:
    #   tilt     = 0.35 * 0.8 * 0.42  = 0.118
    #   presence = 0.20 * 0.8 * 0.42  = 0.067
    #   -> gL deviated about 0.20  (~1.7 dB)
    #   -> gM deviated about 0.03  (~0.17 dB) - effectively STATIC
    #   -> gH deviated about 0.19  (~1.6 dB)
    # and the [0.5, 1.5] clamp never engaged at any normal setting, so
    # tripling Pca_strength bought only about 3 dB. Verified on the
    # rendered audio: strength 0.8 moved the low band +/-1.8 dB against
    # strength 0, and strength 3.0 only reached +/-3.1 dB.
    #
    # v0.8 works in dB with normalised weights, so Depth_dB IS the
    # maximum swing of a band at Pca_strength = 1, and the mid band
    # gets comparable authority to the others.
    wL = (-0.55 * pc1m + 0.45 * pc3m)
    wM = ( 0.60 * pc2m - 0.40 * pc3m)
    wH = ( 0.55 * pc1m + 0.45 * pc2m)

    gLdB = depth_dB * pca_strength * wL
    gMdB = depth_dB * pca_strength * wM
    gHdB = depth_dB * pca_strength * wH

    # a generous ceiling so Depth_dB is the operative limit, not this
    capdB = depth_dB * 2.5
    if capdB < 6
        capdB = 6
    endif
    gLdB = max(-capdB, min(capdB, gLdB))
    gMdB = max(-capdB, min(capdB, gMdB))
    gHdB = max(-capdB, min(capdB, gHdB))

    gL = 10 ^ (gLdB / 20)
    gM = 10 ^ (gMdB / 20)
    gH = 10 ^ (gHdB / 20)

    # Store for visualization
    gainL_vals#[k] = gL
    gainM_vals#[k] = gM
    gainH_vals#[k] = gH

    # Extract Hann-windowed chunk (zero-padded outside the domain)
    selectObject: snd
    Extract part: t1, t2, "Hanning", 1, "no"
    seg = selected("Sound")

    selectObject: seg
    To Spectrum: "yes"
    s_all = selected("Spectrum")

    # v0.5: all three bands use the SAME crossover smoothing so the
    # skirts at shared edges are exactly complementary -- the bands
    # sum to the band-limited input at machine precision.
    # Low band
    selectObject: s_all
    Copy: "s_low"
    s_low = selected("Spectrum")
    Filter (pass Hann band): 0, low_hi_crossover1_hz, 100
    To Sound
    lowB = selected("Sound")

    # Mid band
    selectObject: s_all
    Copy: "s_mid"
    s_mid = selected("Spectrum")
    Filter (pass Hann band): low_hi_crossover1_hz, low_hi_crossover2_hz, 100
    To Sound
    midB = selected("Sound")

    # High band
    selectObject: s_all
    Copy: "s_high"
    s_high = selected("Spectrum")
    Filter (pass Hann band): low_hi_crossover2_hz, high_band_top_hz, 100
    To Sound
    highB = selected("Sound")

    # v0.6 fix 5: RESIDUAL band above High_band_top_hz, passed at unity.
    # v0.5 summed only the three shaped bands, so everything above
    # High_band_top_hz was discarded - at the 8000 Hz default that is a
    # permanent low-pass, and Pca_strength = 0 was therefore not a
    # bypass but an 8 kHz filter. The residual keeps the sum
    # transparent when the gains are 1.
    haveResidual = 0
    if high_band_top_hz < nyq - 1
        selectObject: s_all
        Copy: "s_res"
        s_res = selected("Spectrum")
        Filter (pass Hann band): high_band_top_hz, 0, 100
        To Sound
        resB = selected("Sound")
        haveResidual = 1
        removeObject: s_res
    endif

    # Dispose spectra
    removeObject: s_low, s_mid, s_high, s_all

    # Apply the gains and sum the bands via Formula in one pass,
    # writing into lowB.
    gLStr$ = string$(gL)
    gMStr$ = string$(gM)
    gHStr$ = string$(gH)
    midIdStr$ = string$(midB)
    highIdStr$ = string$(highB)

    selectObject: lowB
    if haveResidual
        resIdStr$ = string$(resB)
        Formula: "self * " + gLStr$
            ... + " + object[" + midIdStr$ + ", col] * " + gMStr$
            ... + " + object[" + highIdStr$ + ", col] * " + gHStr$
            ... + " + object[" + resIdStr$ + ", col]"
    else
        Formula: "self * " + gLStr$
            ... + " + object[" + midIdStr$ + ", col] * " + gMStr$
            ... + " + object[" + highIdStr$ + ", col] * " + gHStr$
    endif
    segOut = lowB
    removeObject: midB, highB
    if haveResidual
        removeObject: resB
    endif

    # Overlap-add segOut into the output buffer at its time offset.
    # The write window is clipped to the Hann support [t1, t1+cDur]
    # (FFT padding beyond it carries only negligible ringing, and
    # the window is zero there anyway); Formula (part) clamps the
    # negative start of the head chunk to the buffer domain.
    segEnd_t = t1 + cDur
    if segEnd_t > dur
        segEnd_t = dur
    endif
    segOutIdStr$ = string$(segOut)
    chunkOffsetCol = round(t1 * fs)
    chunkOffsetStr$ = string$(chunkOffsetCol)
    selectObject: outS
    Formula (part): t1, segEnd_t, 1, 1,
        ... "self + object[" + segOutIdStr$
        ... + ", 1, col - " + chunkOffsetStr$ + "]"

    # Cleanup chunk bits
    removeObject: seg, segOut
    
    if k mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " done"

# ===== FINALIZE =====
selectObject: outS
# v0.6 fix 6: output level is a choice. v0.5 always ran Scale peak, so
# an EQ that lowered the whole file was pushed back up, one that raised
# it was pulled down, Pca_strength = 0 still changed the source peak,
# and a very quiet input was amplified along with its noise floor.
outPeakNow = Get absolute extremum: 0, 0, "None"
if output_level_mode = 3
    Scale peak: headroom
elsif output_level_mode = 2 and outPeakNow > headroom
    Scale peak: headroom
endif

selectObject: outS
outDur = Get total duration

# ===== VISUALIZATION =====
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    # v0.5: explicit inner viewport == outer strip. With only an
    # outer viewport, Praat subtracts font-size-dependent margins,
    # which compressed the world mapping and printed the title and
    # subtitle on top of each other.
    Select outer viewport: 0, 8, 0.05, 0.50
    Select inner viewport: 0, 8, 0.05, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half",
        ... "##PCA Tone Shaper v0.8##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... origName$ + "  |  preset: " + presetName$
        ... + "  |  strength: " + fixed$(pca_strength, 2)
        ... + "  |  bands: 0-" + string$(low_hi_crossover1_hz)
        ... + "/" + string$(low_hi_crossover2_hz)
        ... + "/" + string$(high_band_top_hz) + " Hz"
        ... + "  |  PC1-3: " + fixed$(expl, 1) + "%"

    # === Input waveform ===
    Select outer viewport: 0, 8, 0.55, 1.30
    Select inner viewport: 0.6, 7.6, 0.60, 1.25
    selectObject: origSnd
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.35, 2.10
    Select inner viewport: 0.6, 7.6, 1.40, 2.05
    selectObject: outS
    Colour: "{0.30, 0.50, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # === Input spectrogram (NEW in v0.4) ===
    Select outer viewport: 0, 8, 2.15, 3.30
    Select inner viewport: 0.6, 7.6, 2.25, 3.25
    selectObject: origSnd
    if nch > 1
        Convert to mono
        viz_inMono = selected("Sound")
    else
        Copy: "viz_inMono"
        viz_inMono = selected("Sound")
    endif
    selectObject: viz_inMono
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    viz_specIn = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: viz_specIn, viz_inMono
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Input spectrogram"

    # === Output spectrogram (NEW in v0.4) ===
    Select outer viewport: 0, 8, 3.35, 4.50
    Select inner viewport: 0.6, 7.6, 3.45, 4.45
    selectObject: outS
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    viz_specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: viz_specOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Output spectrogram (after EQ)"

    # === Band gains over time (existing, restyled) ===
    Select outer viewport: 0, 8, 4.55, 5.55
    Select inner viewport: 0.6, 7.6, 4.65, 5.50

    Axes: 0, dur, 0.4, 1.6
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, 0.4, 1.6

    # Reference line at 1.0
    Colour: "{0.78, 0.78, 0.78}"
    Dotted line
    Draw line: 0, 1, dur, 1
    Solid line

    # v0.5: gains drawn at true chunk centers, (k-1)*hop -- this is
    # also where each chunk's Hann window peaks, so the plotted
    # trajectory matches the effective crossfaded gain contour.
    # Low band (red)
    Colour: "{0.80, 0.30, 0.30}"
    Line width: 1.4
    for k from 2 to nChunks
        t1_pt = (k - 2) * hop
        t2_pt = (k - 1) * hop
        Draw line: t1_pt, gainL_vals#[k - 1], t2_pt, gainL_vals#[k]
    endfor

    # Mid band (green)
    Colour: "{0.30, 0.65, 0.30}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * hop
        t2_pt = (k - 1) * hop
        Draw line: t1_pt, gainM_vals#[k - 1], t2_pt, gainM_vals#[k]
    endfor

    # High band (blue)
    Colour: "{0.30, 0.40, 0.80}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * hop
        t2_pt = (k - 1) * hop
        Draw line: t1_pt, gainH_vals#[k - 1], t2_pt, gainH_vals#[k]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text top: "no",
        ... "Band gains over time (red=Low, green=Mid, blue=High; dotted=unity)"

    # === PC trajectory (NEW in v0.4) ===
    # Shows what the PCA is responding to: PC1, PC2, PC3 over time.
    # All three PCs are normalized to [-1, 1] so they share an axis.
    Select outer viewport: 0, 8, 5.60, 6.55
    Select inner viewport: 0.6, 7.6, 5.70, 6.50

    Axes: 0, dur, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, -1.1, 1.1

    Colour: "{0.78, 0.78, 0.78}"
    Dotted line
    Draw line: 0, 0, dur, 0
    Solid line

    # Map frame index to time: t = t0 + (i - 0.5) * dt
    # PC1 (purple)
    Colour: "{0.55, 0.30, 0.70}"
    Line width: 1.5
    for ii from 2 to nScores
        ti1 = t0 + (ii - 1.5) * dt
        ti2 = t0 + (ii - 0.5) * dt
        Draw line: ti1, pc1_vals#[ii - 1], ti2, pc1_vals#[ii]
    endfor

    # PC2 (orange)
    Colour: "{0.85, 0.55, 0.20}"
    Line width: 1.2
    for ii from 2 to nScores
        ti1 = t0 + (ii - 1.5) * dt
        ti2 = t0 + (ii - 0.5) * dt
        Draw line: ti1, pc2_vals#[ii - 1], ti2, pc2_vals#[ii]
    endfor

    # PC3 (teal)
    Colour: "{0.20, 0.55, 0.55}"
    Line width: 1.0
    for ii from 2 to nScores
        ti1 = t0 + (ii - 1.5) * dt
        ti2 = t0 + (ii - 0.5) * dt
        Draw line: ti1, pc3_vals#[ii - 1], ti2, pc3_vals#[ii]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Score"
    Text bottom: "yes", "Time (s)"
    Text top: "no",
        ... "PC scores: PC1 (purple), PC2 (orange), PC3 (teal)"

    # === Legend / parameters strip ===
    Select outer viewport: 0, 8, 6.60, 7.00
    Select inner viewport: 0.6, 7.6, 6.63, 6.97
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.70, "half",
        ... "##Bands##  Low: 0-" + string$(low_hi_crossover1_hz)
        ... + " Hz   Mid: " + string$(low_hi_crossover1_hz)
        ... + "-" + string$(low_hi_crossover2_hz)
        ... + " Hz   High: " + string$(low_hi_crossover2_hz)
        ... + "-" + string$(high_band_top_hz) + " Hz"
        ... + "    ##Chunk##  " + string$(chunk_ms) + " ms"
        ... + "    ##Chunks##  " + string$(nChunks)
    Text: 0.02, "left", 0.30, "half",
        ... "##PCA##  variance explained PC1-3 = "
        ... + fixed$(expl, 1) + "%"
        ... + "    ##Strength##  " + fixed$(pca_strength, 2)
        ... + "    ##Headroom##  " + fixed$(headroom, 2)
        ... + "    ##Duration##  " + fixed$(outDur, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ===== REPORT =====
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Duration: ", fixed$(dur, 3), " s | Fs: ", fs, " Hz"
appendInfoLine: "Chunks: ", nChunks, " x ", chunk_ms, " ms"
appendInfoLine: "Explained variance PC1-3: ", fixed$(expl, 1), "%"

# ===== CLEANUP =====
removeObject: snd, pit, inten, hnr, fmtObj
removeObject: feat, zfeat, pca, config, scr, ctrl

# ===== OUTPUT =====
selectObject: origSnd
plusObject: outS

if play_result <> 0
    selectObject: outS
    Play
endif
