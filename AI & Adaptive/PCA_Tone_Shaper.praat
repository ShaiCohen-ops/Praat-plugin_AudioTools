# ============================================================
# Praat AudioTools - PCA_Tone_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PCA Tone Shaper - Maps PCA-derived timbre features to
#   dynamic 3-band EQ for adaptive spectral shaping.
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

form PCA Tone Shaper v0.4
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Warm (Bass Boost)
        option Bright (Treble Boost)
        option Presence (Mid Focus)
        option Smooth (Reduce Harshness)
        option Dynamic (Full Range)
    comment === Processing ===
    positive Chunk_ms 200
    positive Frame_step_seconds 0.01
    positive Pca_strength 0.8
    comment === Frequency Bands (Hz) ===
    positive Low_hi_crossover1_hz 200
    positive Low_hi_crossover2_hz 2000
    positive High_band_top_hz 8000
    comment === Analysis ===
    positive Max_formant_hz 5500
    integer N_formants 5
    positive F0_min 75
    positive F0_max 600
    comment === Output ===
    positive Headroom 0.97
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===== PRESET LOGIC =====
if preset = 2
    # Warm
    pca_strength = 1.0
    low_hi_crossover1_hz = 250
    low_hi_crossover2_hz = 1500
    presetName$ = "Warm"
elsif preset = 3
    # Bright
    pca_strength = 1.0
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2500
    presetName$ = "Bright"
elsif preset = 4
    # Presence
    pca_strength = 0.9
    low_hi_crossover1_hz = 300
    low_hi_crossover2_hz = 3000
    presetName$ = "Presence"
elsif preset = 5
    # Smooth
    pca_strength = 0.6
    low_hi_crossover1_hz = 150
    low_hi_crossover2_hz = 2000
    presetName$ = "Smooth"
elsif preset = 6
    # Dynamic
    pca_strength = 1.2
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "Dynamic"
else
    presetName$ = "Manual"
endif

# ===== SETUP =====
clearinfo
writeInfoLine: "=== PCA Tone Shaper v0.4 ==="
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

# ===== GUARDS =====
nyq = fs / 2
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
To Pitch: 0, f0_min, f0_max
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
if nF < 3
    exitScript: "Not enough frames for PCA (need >= 3)."
endif
t0 = Get start time
dt = Get time step
if dt <= 0
    dt = frame_step_seconds
endif

appendInfoLine: "  ", nF, " frames"

# ===== FEATURE TABLE (nF x 8) =====
Create TableOfReal: "feat", nF, 8
feat = selected("TableOfReal")

for i from 1 to nF
    t = t0 + (i - 0.5) * dt
    
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

    selectObject: hnr
    hnrVal = Get value in frame: i
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
    rg = mx - mn
    if rg = 0
        rg = 1
    endif
    for ii from 1 to nScores
        selectObject: scr
        vv = Get value: ii, pcNum
        nv = 2*((vv - mn)/rg) - 1
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

# ===== CHUNKED PROCESSING =====
appendInfoLine: "Processing chunks..."

cDur = chunk_ms / 1000
if cDur < dt
    cDur = dt
endif
nChunks = round(dur / cDur + 0.4999)
if nChunks < 1
    nChunks = 1
endif

appendInfoLine: "  ", nChunks, " chunks of ", chunk_ms, " ms"

# Store gains for visualization
gainL_vals# = zero#(nChunks)
gainM_vals# = zero#(nChunks)
gainH_vals# = zero#(nChunks)

# v0.4: Pre-allocate the output buffer at the input duration.
# Previous version concatenated each chunk in a loop, rebuilding
# the entire growing buffer at every step (O(n^2)). Now we write
# each processed chunk into the pre-allocated buffer at its
# original time offset using Formula (part).
outS = Create Sound from formula: origName$ + "_PCATone_" + presetName$,
    ... 1, 0, dur, fs, "0"

for k from 1 to nChunks
    t1 = (k - 1) * cDur
    t2 = t1 + cDur
    if t2 > dur
        t2 = dur
    endif
    if t2 > t1
        # Frame indices
        f1i = round((t1 - t0) / dt - 0.5) + 1
        f2i = round((t2 - t0) / dt + 0.5)
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
        pc1m = a1 / effCnt
        pc2m = a2 / effCnt
        pc3m = a3 / effCnt

        # Map to band gains
        tilt = 0.35 * pca_strength * pc1m
        presence = 0.20 * pca_strength * pc2m
        body = 0.30 * pca_strength * pc3m
        gL = 1.0 - tilt + 0.8*body
        gM = 1.0 + 0.3*presence - 0.2*body
        gH = 1.0 + 1.2*tilt + 0.7*presence - 0.2*body
        
        if gL < 0.5
            gL = 0.5
        endif
        if gL > 1.5
            gL = 1.5
        endif
        if gM < 0.5
            gM = 0.5
        endif
        if gM > 1.5
            gM = 1.5
        endif
        if gH < 0.5
            gH = 0.5
        endif
        if gH > 1.5
            gH = 1.5
        endif
        
        # Store for visualization
        gainL_vals#[k] = gL
        gainM_vals#[k] = gM
        gainH_vals#[k] = gH

        # Extract chunk
        selectObject: snd
        Extract part: t1, t2, "Hamming", 1, "yes"
        seg = selected("Sound")

        selectObject: seg
        To Spectrum: "yes"
        s_all = selected("Spectrum")

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
        Filter (pass Hann band): low_hi_crossover1_hz, low_hi_crossover2_hz, 200
        To Sound
        midB = selected("Sound")

        # High band
        selectObject: s_all
        Copy: "s_high"
        s_high = selected("Spectrum")
        Filter (pass Hann band): low_hi_crossover2_hz, high_band_top_hz, 500
        To Sound
        highB = selected("Sound")

        # Dispose spectra
        removeObject: s_low, s_mid, s_high, s_all

        # v0.4 FIX: previous version applied gains to each band
        # then mixed via "Combine to stereo + Convert to mono"
        # twice, which AVERAGES instead of sums. With gL=gM=gH=1.0
        # the previous output was low/4 + mid/4 + high/2 instead
        # of low+mid+high. Now we apply the gains and sum directly
        # via Formula in a single pass, writing into lowB.
        gLStr$ = string$(gL)
        gMStr$ = string$(gM)
        gHStr$ = string$(gH)
        midIdStr$ = string$(midB)
        highIdStr$ = string$(highB)

        selectObject: lowB
        Formula: "self * " + gLStr$
            ... + " + object[" + midIdStr$ + ", col] * " + gMStr$
            ... + " + object[" + highIdStr$ + ", col] * " + gHStr$
        segOut = lowB
        removeObject: midB, highB

        # v0.4: write segOut into the pre-allocated output buffer
        # at its time offset. Previous version called Concatenate
        # in a loop — O(n^2) cost.
        selectObject: segOut
        segOutDur = Get total duration
        segEnd_t = t1 + segOutDur
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
    endif
    
    if k mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " done"

# ===== FINALIZE =====
selectObject: outS
Scale peak: headroom

selectObject: outS
outDur = Get total duration

# ===== VISUALIZATION =====
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0.05, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half",
        ... "##PCA Tone Shaper v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
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

    # Low band (red)
    Colour: "{0.80, 0.30, 0.30}"
    Line width: 1.4
    for k from 2 to nChunks
        t1_pt = (k - 2) * cDur
        t2_pt = (k - 1) * cDur
        Draw line: t1_pt, gainL_vals#[k - 1], t2_pt, gainL_vals#[k]
    endfor

    # Mid band (green)
    Colour: "{0.30, 0.65, 0.30}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * cDur
        t2_pt = (k - 1) * cDur
        Draw line: t1_pt, gainM_vals#[k - 1], t2_pt, gainM_vals#[k]
    endfor

    # High band (blue)
    Colour: "{0.30, 0.40, 0.80}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * cDur
        t2_pt = (k - 1) * cDur
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
