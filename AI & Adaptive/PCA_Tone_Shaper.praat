# ============================================================
# Praat AudioTools - PCA_Tone_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
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
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSnd = selected("Sound")
origName$ = selected$("Sound")

form PCA Tone Shaper v0.3
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
writeInfoLine: "=== PCA Tone Shaper v0.3 ==="
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

for col from 1 to nCols
    selectObject: feat
    sum = 0
    for row from 1 to nRows
        val = Get value: row, col
        sum = sum + val
    endfor
    mean = sum / nRows
    sumSq = 0
    for row from 1 to nRows
        selectObject: feat
        val = Get value: row, col
        diff = val - mean
        sumSq = sumSq + diff*diff
    endfor
    sd = sqrt(sumSq / nRows)
    if sd = 0
        sd = 1
    endif
    for row from 1 to nRows
        selectObject: feat
        val = Get value: row, col
        z = (val - mean) / sd
        selectObject: zfeat
        Set value: row, col, z
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

firstDone = 0
outS = 0

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

        # Apply gains (fixed: use string$ for variable)
        gLStr$ = string$(gL)
        gMStr$ = string$(gM)
        gHStr$ = string$(gH)
        
        selectObject: lowB
        Formula: "self * " + gLStr$
        selectObject: midB
        Formula: "self * " + gMStr$
        selectObject: highB
        Formula: "self * " + gHStr$

        # Mix bands
        selectObject: lowB
        plusObject: midB
        Combine to stereo
        stereo1 = selected("Sound")
        Convert to mono
        lowMid = selected("Sound")

        selectObject: lowMid
        plusObject: highB
        Combine to stereo
        stereo2 = selected("Sound")
        Convert to mono
        segOut = selected("Sound")

        # Cleanup intermediate
        removeObject: stereo1, stereo2, lowMid

        if firstDone = 0
            selectObject: segOut
            Copy: origName$ + "_PCATone_" + presetName$
            outS = selected("Sound")
            firstDone = 1
            removeObject: segOut
        else
            selectObject: outS
            plusObject: segOut
            Concatenate
            newOut = selected("Sound")
            removeObject: outS, segOut
            outS = newOut
        endif

        # Cleanup chunk bits
        removeObject: seg, lowB, midB, highB
    endif
    
    if k mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " done"

# ===== FINALIZE =====
selectObject: outS
Scale peak: headroom
Rename: origName$ + "_PCATone_" + presetName$

selectObject: outS
outDur = Get total duration

# ===== VISUALIZATION =====
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "PCA Tone Shaper: " + origName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: origSnd
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: outS
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Band gains over time
    Select outer viewport: 0, 8, 2.7, 4.2
    Select inner viewport: 0.6, 7.6, 2.9, 4.1
    
    Axes: 0, dur, 0.4, 1.6
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, 0.4, 1.6
    
    # Reference line at 1.0
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 1, dur, 1
    Solid line
    
    # Low band (red)
    Colour: "{0.8, 0.3, 0.3}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * cDur
        t2_pt = (k - 1) * cDur
        Draw line: t1_pt, gainL_vals#[k-1], t2_pt, gainL_vals#[k]
    endfor
    
    # Mid band (green)
    Colour: "{0.3, 0.7, 0.3}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * cDur
        t2_pt = (k - 1) * cDur
        Draw line: t1_pt, gainM_vals#[k-1], t2_pt, gainM_vals#[k]
    endfor
    
    # High band (blue)
    Colour: "{0.3, 0.4, 0.8}"
    for k from 2 to nChunks
        t1_pt = (k - 2) * cDur
        t2_pt = (k - 1) * cDur
        Draw line: t1_pt, gainH_vals#[k-1], t2_pt, gainH_vals#[k]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 8
    Colour: "{0.8, 0.3, 0.3}"
    Text: 1.2, "centre", 0.5, "half", "— Low (0-" + string$(low_hi_crossover1_hz) + " Hz)"
    Colour: "{0.3, 0.7, 0.3}"
    Text: 1.2, "centre", 2.5, "half", "— Mid (" + string$(low_hi_crossover1_hz) + "-" + string$(low_hi_crossover2_hz) + " Hz)"
    Colour: "{0.3, 0.4, 0.8}"
    Text: 1.2, "centre", 4.5, "half", "— High (" + string$(low_hi_crossover2_hz) + "-" + string$(high_band_top_hz) + " Hz)"
    
    Font size: 10
    Colour: "Black"
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
