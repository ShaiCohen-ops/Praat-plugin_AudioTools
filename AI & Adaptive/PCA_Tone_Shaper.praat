# ============================================================
# Praat AudioTools - PCA_Tone_Shaper.praat
# Version: 1.0 (2026) - Suite-standard visualization
# Author: Shai Cohen
# License: MIT
# ============================================================
#
# v0.9 architecture
#   * FormantPath/Formant is ANALYSIS ONLY.
#   * Undefined or structurally implausible formants are never replaced
#     by a canonical vowel template.
#   * Invalid formant spans are interpolated from this file's own valid
#     landmarks. If too few frames are valid, formant dimensions are
#     removed from the PCA entirely.
#   * Fixed EQ bands are filtered once; PCA trajectories drive smooth
#     IntensityTier gains. No per-chunk FFT/WOLA is needed.
#   * Analysis may be mono; processing preserves all input channels.
# v1.0 visualization update
#   * Audio analysis, PCA control generation, adaptive EQ and rendering
#     are unchanged from v0.9.
#   * Standardized the 8-inch Praat AudioTools page, title/subtitle,
#     explicit inner viewports, typography, neutral panel colours,
#     summary strip and full-page export viewport.
#   * Added explicit panel titles and safe escaping for drawn object names.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSnd = selected("Sound")
origName$ = selected$("Sound")

form PCA Tone Shaper v1.0  (validity-aware adaptive EQ)
    optionmenu Preset: 1
        option Manual
        option Low crossover (200/2000 Hz)
        option Wide band (150/3000 Hz)
        option Mid focused (300/1800 Hz)
        option Gentle (low strength)
        option Strong (full range, high strength)
    positive Control_smoothing_ms 200
    positive Frame_step_seconds 0.01
    real Pca_strength 1.0
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

# ---------- validation ----------
if control_smoothing_ms <= 0
    exitScript: "Control_smoothing_ms must be greater than 0."
endif
if frame_step_seconds <= 0
    exitScript: "Frame_step_seconds must be greater than 0."
endif
if pca_strength < 0
    pca_strength = 0
endif
if pca_strength > 1.5
    pca_strength = 1.5
endif
if depth_dB <= 0
    exitScript: "Depth_dB must be greater than 0."
endif
if f0_min <= 0 or f0_max <= f0_min
    exitScript: "Need 0 < F0_min < F0_max."
endif
if n_formants < 3
    n_formants = 3
endif
if headroom <= 0 or headroom > 1
    headroom = 0.97
endif

# ---------- presets ----------
if preset = 2
    pca_strength = 0.8
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "LowCrossover"
elsif preset = 3
    pca_strength = 0.8
    low_hi_crossover1_hz = 150
    low_hi_crossover2_hz = 3000
    presetName$ = "WideBand"
elsif preset = 4
    pca_strength = 0.8
    low_hi_crossover1_hz = 300
    low_hi_crossover2_hz = 1800
    presetName$ = "MidFocused"
elsif preset = 5
    pca_strength = 0.4
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "Gentle"
elsif preset = 6
    pca_strength = 1.4
    low_hi_crossover1_hz = 200
    low_hi_crossover2_hz = 2000
    presetName$ = "Strong"
else
    presetName$ = "Manual"
endif

clearinfo
writeInfoLine: "=== PCA Tone Shaper v1.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Validity-aware FormantPath analysis; full-file dynamic 3-band EQ"
appendInfoLine: ""

selectObject: origSnd
xmin = Get start time
xmax = Get end time
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels
srcPeak = Get absolute extremum: 0, 0, "None"

if dur <= 0
    exitScript: "Invalid sound duration."
endif
if srcPeak < 1e-8
    exitScript: "The selected Sound is silent or near-silent."
endif

nyq = fs / 2
if nyq < 2000
    exitScript: "Sample rate too low: Nyquist must be at least 2000 Hz."
endif
if low_hi_crossover1_hz >= low_hi_crossover2_hz
    exitScript: "Low crossover must be below high crossover."
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
maxFmtHz = min(max_formant_hz, nyq - 200)
if maxFmtHz < 1200
    maxFmtHz = nyq - 100
endif
f0_max = min(f0_max, nyq - 50)

appendInfoLine: "Input: ", fixed$(dur, 3), " s | ", fs, " Hz | ", nch, " channel(s)"
appendInfoLine: "Bands: 0-", fixed$(low_hi_crossover1_hz,0), " / ",
    ... fixed$(low_hi_crossover1_hz,0), "-", fixed$(low_hi_crossover2_hz,0), " / ",
    ... fixed$(low_hi_crossover2_hz,0), "-", fixed$(high_band_top_hz,0), " Hz"

# True bypass: no analysis, no channel conversion, no level stage.
if pca_strength = 0
    selectObject: origSnd
    outS = Copy: origName$ + "_PCATone_Bypass"
    appendInfoLine: "PCA strength = 0 -> exact bypass."
    if play_result
        selectObject: outS
        Play
    endif
    selectObject: outS
    goto FINAL_RETURN
endif

# ---------- mono analysis copy only ----------
selectObject: origSnd
if nch > 1
    snd = Convert to mono
    Rename: "PCA_analysis_mono"
else
    snd = Copy: "PCA_analysis_mono"
endif

appendInfoLine: "Extracting analysis features..."
selectObject: snd
pit = To Pitch: frame_step_seconds, f0_min, f0_max
selectObject: snd
inten = To Intensity: max(50, f0_min), 0, "yes"
selectObject: snd
hnr = To Harmonicity (cc): frame_step_seconds, f0_min, 0.1, 1.0

# FormantPath gives a more robust candidate path than one fixed Burg fit.
selectObject: snd
formantCeil = min(maxFmtHz, (nyq - 50) / 1.22)
formantPath = To FormantPath (burg): frame_step_seconds, n_formants, formantCeil, 0.030, 35, 0.05, 4
formantObj = Extract Formant

selectObject: pit
nF = Get number of frames
if nF < 5
    exitScript: "Not enough analysis frames for PCA (need at least 5)."
endif
pitchX1 = Get time from frame number: 1
dt = Get time step
if dt <= 0
    dt = frame_step_seconds
endif

rawF1# = zero#(nF)
rawF2# = zero#(nF)
rawF3# = zero#(nF)
rawF0# = zero#(nF)
rawInt# = zero#(nF)
rawHnr# = zero#(nF)
fmtValid# = zero#(nF)
hnrValid# = zero#(nF)
intValid# = zero#(nF)
time# = zero#(nF)

validFmtCount = 0
validHnrCount = 0
validIntCount = 0

# Structural validity constants. They reject the narrow, collapsed
# pseudo-formants that Burg can invent on a sine, while remaining broad
# enough for non-speech musical material.
minFmtBandwidth = 15
minFmtGap = 70
minFmtSpan = 450

for i from 1 to nF
    selectObject: pit
    t = Get time from frame number: i
    time#[i] = t
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 < 0
        f0 = 0
    endif
    rawF0#[i] = f0

    selectObject: formantObj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    bw1 = Get bandwidth at time: 1, t, "Hertz", "Linear"
    bw2 = Get bandwidth at time: 2, t, "Hertz", "Linear"
    bw3 = Get bandwidth at time: 3, t, "Hertz", "Linear"

    isValid = 1
    if f1 = undefined or f2 = undefined or f3 = undefined
        isValid = 0
    elsif bw1 = undefined or bw2 = undefined or bw3 = undefined
        isValid = 0
    elsif f1 <= 0 or f2 <= f1 or f3 <= f2 or f3 >= nyq - 20
        isValid = 0
    elsif f2 - f1 < minFmtGap or f3 - f2 < minFmtGap
        isValid = 0
    elsif f3 - f1 < max(minFmtSpan, 1.5 * f0)
        isValid = 0
    elsif bw1 < minFmtBandwidth or bw2 < minFmtBandwidth or bw3 < minFmtBandwidth
        isValid = 0
    endif

    if isValid
        rawF1#[i] = f1
        rawF2#[i] = f2
        rawF3#[i] = f3
        fmtValid#[i] = 1
        validFmtCount += 1
    endif

    selectObject: inten
    iv = Get value at time: t, "cubic"
    if iv <> undefined
        rawInt#[i] = iv
        intValid#[i] = 1
        validIntCount += 1
    endif

    selectObject: hnr
    hv = Get value at time: t, "Cubic"
    if hv <> undefined
        rawHnr#[i] = hv
        hnrValid#[i] = 1
        validHnrCount += 1
    endif
endfor

fmtFrac = validFmtCount / nF
appendInfoLine: "  Formant-valid frames: ", validFmtCount, "/", nF,
    ... " (", fixed$(100*fmtFrac,1), "%)"

# ---------- interpolation helpers ----------
# Fill an array only from its OWN valid measurements. Interior gaps are
# linearly interpolated; leading/trailing gaps hold the nearest valid value.
procedure interpolateFeature: .n
    .first = 0
    for .i from 1 to .n
        if interpValid#[.i] = 1 and .first = 0
            .first = .i
        endif
    endfor
    if .first = 0
        interpolateFeature.have = 0
    else
        interpolateFeature.have = 1
        .firstVal = interpData#[.first]
        for .j from 1 to .first - 1
            interpData#[.j] = .firstVal
        endfor
        .prev = .first
        for .i from .first + 1 to .n
            if interpValid#[.i] = 1
                .next = .i
                .den = .next - .prev
                if .den > 1
                    .v0 = interpData#[.prev]
                    .v1 = interpData#[.next]
                    for .j from .prev + 1 to .next - 1
                        .u = (.j - .prev) / .den
                        interpData#[.j] = .v0 + (.v1 - .v0) * .u
                    endfor
                endif
                .prev = .next
            endif
        endfor
        .lastVal = interpData#[.prev]
        for .j from .prev + 1 to .n
            interpData#[.j] = .lastVal
        endfor
    endif
endproc

# Formants are included only when there is enough reliable evidence.
minValidFrames = max(5, ceiling(0.15 * nF))
formantFeaturesActive = 0
if validFmtCount >= minValidFrames
    interpValid# = fmtValid#
    interpData# = rawF1#
    @interpolateFeature: nF
    rawF1# = interpData#
    interpData# = rawF2#
    @interpolateFeature: nF
    rawF2# = interpData#
    interpData# = rawF3#
    @interpolateFeature: nF
    rawF3# = interpData#
    formantFeaturesActive = 1
    appendInfoLine: "  Formant dimensions ACTIVE; invalid spans interpolated from real landmarks."
else
    appendInfoLine: "  Formant dimensions DISABLED: insufficient reliable landmarks."
endif

# HNR and intensity use the same no-invented-template policy.
if validHnrCount > 0
    interpValid# = hnrValid#
    interpData# = rawHnr#
    @interpolateFeature: nF
    rawHnr# = interpData#
else
    for i from 1 to nF
        rawHnr#[i] = 0
    endfor
endif
if validIntCount > 0
    interpValid# = intValid#
    interpData# = rawInt#
    @interpolateFeature: nF
    rawInt# = interpData#
else
    for i from 1 to nF
        rawInt#[i] = 0
    endfor
endif

# If no reliable formant structure exists, HNR alone is not enough to
# justify a time-varying 3-band timbre map on an otherwise static signal.
# This rejects numerical HNR flutter on pure tones / steady narrowband input.
if formantFeaturesActive = 0
    voicedCount = 0
    f0Sum = 0
    for i from 1 to nF
        if rawF0#[i] > 0
            voicedCount += 1
            f0Sum += rawF0#[i]
        endif
    endfor
    if voicedCount > 0
        f0Mean = f0Sum / voicedCount
        f0SS = 0
        for i from 1 to nF
            if rawF0#[i] > 0
                d = rawF0#[i] - f0Mean
                f0SS += d*d
            endif
        endfor
        f0SD = sqrt(f0SS / voicedCount)
    else
        f0SD = 0
    endif
    intSum = 0
    for i from 1 to nF
        intSum += rawInt#[i]
    endfor
    intMean = intSum / nF
    intSS = 0
    for i from 1 to nF
        d = rawInt#[i] - intMean
        intSS += d*d
    endfor
    intSD = sqrt(intSS / nF)

    if f0SD < 0.5 and intSD < 0.05
        appendInfoLine: "  No robust formants + static F0/intensity -> exact bypass (HNR-only motion rejected)."
        selectObject: origSnd
        outS = Copy: origName$ + "_PCATone_NarrowbandBypass"
        removeObject: snd, pit, inten, hnr, formantPath, formantObj
        goto FINAL_RETURN
    endif
endif

# ---------- feature table ----------
if formantFeaturesActive
    nBaseCols = 8
else
    nBaseCols = 3
endif
Create TableOfReal: "feat", nF, nBaseCols
feat = selected("TableOfReal")

for i from 1 to nF
    if formantFeaturesActive
        f1 = rawF1#[i]
        f2 = rawF2#[i]
        f3 = rawF3#[i]
        selectObject: feat
        Set value: i, 1, f1
        Set value: i, 2, f2
        Set value: i, 3, f3
        Set value: i, 4, f2 / max(f1, 1)
        Set value: i, 5, f3 / max(f2, 1)
        Set value: i, 6, rawF0#[i]
        Set value: i, 7, rawInt#[i]
        Set value: i, 8, rawHnr#[i]
    else
        selectObject: feat
        Set value: i, 1, rawF0#[i]
        Set value: i, 2, rawInt#[i]
        Set value: i, 3, rawHnr#[i]
    endif
endfor

# ---------- z-score and remove constant dimensions ----------
mean# = zero#(nBaseCols)
sd# = zero#(nBaseCols)
activeMap# = zero#(nBaseCols)
activeCols = 0
for c from 1 to nBaseCols
    s = 0
    for i from 1 to nF
        selectObject: feat
        v = Get value: i, c
        s += v
    endfor
    mu = s / nF
    ss = 0
    for i from 1 to nF
        selectObject: feat
        v = Get value: i, c
        d = v - mu
        ss += d*d
    endfor
    sdv = sqrt(ss / nF)
    mean#[c] = mu
    sd#[c] = sdv
    if sdv > 1e-9
        activeCols += 1
        activeMap#[activeCols] = c
    endif
endfor

if activeCols = 0
    appendInfoLine: "No time-varying analysis dimensions -> exact dry copy."
    selectObject: origSnd
    outS = Copy: origName$ + "_PCATone_StaticBypass"
    removeObject: snd, pit, inten, hnr, formantPath, formantObj, feat
    if play_result
        selectObject: outS
        Play
    endif
    selectObject: outS
    goto FINAL_RETURN
endif

Create TableOfReal: "zfeat", nF, activeCols
zfeat = selected("TableOfReal")
for ac from 1 to activeCols
    c = activeMap#[ac]
    mu = mean#[c]
    sdv = sd#[c]
    for i from 1 to nF
        selectObject: feat
        v = Get value: i, c
        selectObject: zfeat
        Set value: i, ac, (v - mu) / sdv
    endfor
endfor

# ---------- PCA ----------
appendInfoLine: "Running PCA on ", activeCols, " active dimensions..."
selectObject: zfeat
To PCA
pca = selected("PCA")
nPC = min(3, activeCols)
selectObject: zfeat
plusObject: pca
To Configuration: nPC
config = selected("Configuration")
selectObject: config
To TableOfReal
scr = selected("TableOfReal")

selectObject: pca
fracExpl = Get fraction variance accounted for: 1, nPC
expl = 100 * fracExpl
appendInfoLine: "  PC1-PC", nPC, " explain ", fixed$(expl,1), "% variance"

pc1# = zero#(nF)
pc2# = zero#(nF)
pc3# = zero#(nF)
pcVar# = zero#(3)

for pc from 1 to 3
    if pc <= nPC
        s = 0
        for i from 1 to nF
            selectObject: scr
            v = Get value: i, pc
            s += v
        endfor
        mu = s / nF
        ss = 0
        for i from 1 to nF
            selectObject: scr
            v = Get value: i, pc
            d = v - mu
            ss += d*d
        endfor
        sdv = sqrt(ss / max(1, nF - 1))
        pcVar#[pc] = sdv*sdv
        for i from 1 to nF
            selectObject: scr
            v = Get value: i, pc
            if sdv > 1e-9
                nv = (v - mu) / (2.5 * sdv)
                nv = max(-1, min(1, nv))
            else
                nv = 0
            endif
            if pc = 1
                pc1#[i] = nv
            elsif pc = 2
                pc2#[i] = nv
            else
                pc3#[i] = nv
            endif
        endfor
    endif
endfor

# Gate axes that carry negligible variance within PC1..PC3.
totVar = pcVar#[1] + pcVar#[2] + pcVar#[3]
if totVar <= 1e-12
    totVar = 1
endif
for pc from 1 to 3
    share = pcVar#[pc] / totVar
    if share < 0.02
        if pc = 1
            for i from 1 to nF
                pc1#[i] = 0
            endfor
        elsif pc = 2
            for i from 1 to nF
                pc2#[i] = 0
            endfor
        else
            for i from 1 to nF
                pc3#[i] = 0
            endfor
        endif
    endif
endfor

# ---------- zero-phase control smoothing ----------
# Control_smoothing_ms is now the control smoothing timescale, not an FFT block size.
tau = max(dt, control_smoothing_ms / 1000 / 3)
alpha = dt / (tau + dt)

procedure smoothControl: .n
    smOut#[1] = smIn#[1]
    for .i from 2 to .n
        smOut#[.i] = smOut#[.i-1] + alpha * (smIn#[.i] - smOut#[.i-1])
    endfor
    for .i from .n - 1 to 1
        smOut#[.i] = smOut#[.i+1] + alpha * (smOut#[.i] - smOut#[.i+1])
    endfor
    .mx = 0
    for .i from 1 to .n
        .a = abs(smOut#[.i])
        if .a > .mx
            .mx = .a
        endif
    endfor
    if .mx > 1e-9
        for .i from 1 to .n
            smOut#[.i] = smOut#[.i] / .mx
        endfor
    else
        for .i from 1 to .n
            smOut#[.i] = 0
        endfor
    endif
endproc

sm1# = zero#(nF)
sm2# = zero#(nF)
sm3# = zero#(nF)
smIn# = pc1#
smOut# = sm1#
@smoothControl: nF
sm1# = smOut#
smIn# = pc2#
smOut# = sm2#
@smoothControl: nF
sm2# = smOut#
smIn# = pc3#
smOut# = sm3#
@smoothControl: nF
sm3# = smOut#

# ---------- build dB gain tiers ----------
gLdB# = zero#(nF)
gMdB# = zero#(nF)
gHdB# = zero#(nF)
capdB = max(6, depth_dB * 2.5)

for i from 1 to nF
    wL = -0.55 * sm1#[i] + 0.45 * sm3#[i]
    wM =  0.60 * sm2#[i] - 0.40 * sm3#[i]
    wH =  0.55 * sm1#[i] + 0.45 * sm2#[i]
    gLdB#[i] = max(-capdB, min(capdB, depth_dB * pca_strength * wL))
    gMdB#[i] = max(-capdB, min(capdB, depth_dB * pca_strength * wM))
    gHdB#[i] = max(-capdB, min(capdB, depth_dB * pca_strength * wH))
endfor

lowTier = Create IntensityTier: "PCA_low_gain", xmin, xmax
midTier = Create IntensityTier: "PCA_mid_gain", xmin, xmax
highTier = Create IntensityTier: "PCA_high_gain", xmin, xmax

selectObject: lowTier
Add point: xmin, gLdB#[1]
selectObject: midTier
Add point: xmin, gMdB#[1]
selectObject: highTier
Add point: xmin, gHdB#[1]
for i from 1 to nF
    t = time#[i]
    if t >= xmin and t <= xmax
        selectObject: lowTier
        Add point: t, gLdB#[i]
        selectObject: midTier
        Add point: t, gMdB#[i]
        selectObject: highTier
        Add point: t, gHdB#[i]
    endif
endfor
selectObject: lowTier
Add point: xmax, gLdB#[nF]
selectObject: midTier
Add point: xmax, gMdB#[nF]
selectObject: highTier
Add point: xmax, gHdB#[nF]

# ---------- fixed bands: filter once, modulate over time ----------
appendInfoLine: "Rendering full-file dynamic bands..."
selectObject: origSnd
Filter (pass Hann band): 0, low_hi_crossover1_hz, 100
lowB = selected("Sound")
selectObject: origSnd
Filter (pass Hann band): low_hi_crossover1_hz, low_hi_crossover2_hz, 100
midB = selected("Sound")
selectObject: origSnd
Filter (pass Hann band): low_hi_crossover2_hz, high_band_top_hz, 100
highB = selected("Sound")

# Exact complement residual: guarantees unity reconstruction when gains=1.
selectObject: origSnd
resB = Copy: "PCA_residual"
lowId$ = string$(lowB)
midId$ = string$(midB)
highId$ = string$(highB)
selectObject: resB
Formula: "self - object[" + lowId$ + ", row, col] - object[" + midId$ + ", row, col] - object[" + highId$ + ", row, col]"

selectObject: lowB
plusObject: lowTier
lowG = Multiply: "no"
selectObject: midB
plusObject: midTier
midG = Multiply: "no"
selectObject: highB
plusObject: highTier
highG = Multiply: "no"

midGId$ = string$(midG)
highGId$ = string$(highG)
resId$ = string$(resB)
selectObject: lowG
Formula: "self + object[" + midGId$ + ", row, col] + object[" + highGId$ + ", row, col] + object[" + resId$ + ", row, col]"
outS = selected("Sound")
Rename: origName$ + "_PCATone_" + presetName$

# ---------- output level ----------
selectObject: outS
outPeak = Get absolute extremum: 0, 0, "None"
if output_level_mode = 3
    Scale peak: headroom
elsif output_level_mode = 2 and outPeak > headroom
    Scale peak: headroom
endif

selectObject: outS
outChannels = Get number of channels
outPeakFinal = Get absolute extremum: 0, 0, "None"
appendInfoLine: "Output: ", outChannels, " channel(s) | peak ", fixed$(outPeakFinal,4)
if formantFeaturesActive
    formantPolicy$ = "valid/interpolated"
    formantState$ = "ACTIVE"
else
    formantPolicy$ = "disabled - insufficient confidence"
    formantState$ = "DISABLED"
endif
appendInfoLine: "Formant policy: ", formantPolicy$
appendInfoLine: "Done."

# ---------- visualization ----------
if draw_visualization
    pageHeight = 6.90
    Erase all
    Select outer viewport: 0, 8, 0, pageHeight

    # Draw-safe source name
    vizOrigName$ = replace$(origName$, "_", "\_ ", 0)

    if output_level_mode = 1
        levelMode$ = "Preserve gain"
    elsif output_level_mode = 2
        levelMode$ = "Conditional limiter"
    else
        levelMode$ = "Normalize to headroom"
    endif

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PCA Tone Shaper v1.0##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizOrigName$ + " | " + presetName$ + " | PCA strength " + fixed$(pca_strength, 2) + " | depth " + fixed$(depth_dB, 1) + " dB"

    # === PC trajectories ===
    Select outer viewport: 0, 8, 0.65, 2.25
    Select inner viewport: 0.60, 7.70, 0.84, 2.03
    Axes: xmin, xmax, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", xmin, xmax, -1.1, 1.1

    Colour: "{0.75, 0.25, 0.25}"
    for i from 2 to nF
        Draw line: time#[i-1], sm1#[i-1], time#[i], sm1#[i]
    endfor
    Colour: "{0.25, 0.55, 0.25}"
    for i from 2 to nF
        Draw line: time#[i-1], sm2#[i-1], time#[i], sm2#[i]
    endfor
    Colour: "{0.25, 0.35, 0.75}"
    for i from 2 to nF
        Draw line: time#[i-1], sm3#[i-1], time#[i], sm3#[i]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "PC control"
    Text bottom: "no", "Time (s)"
    Text top: "no", "PCA Control Trajectories | PC1 = red | PC2 = green | PC3 = blue"

    # === Gain trajectories ===
    Select outer viewport: 0, 8, 2.45, 4.05
    Select inner viewport: 0.60, 7.70, 2.64, 3.83
    Axes: xmin, xmax, -capdB, capdB
    Paint rectangle: "{0.97, 0.97, 0.97}", xmin, xmax, -capdB, capdB

    Colour: "{0.80, 0.80, 0.80}"
    Dashed line
    Draw line: xmin, 0, xmax, 0
    Solid line

    Colour: "{0.75, 0.25, 0.25}"
    for i from 2 to nF
        Draw line: time#[i-1], gLdB#[i-1], time#[i], gLdB#[i]
    endfor
    Colour: "{0.25, 0.55, 0.25}"
    for i from 2 to nF
        Draw line: time#[i-1], gMdB#[i-1], time#[i], gMdB#[i]
    endfor
    Colour: "{0.25, 0.35, 0.75}"
    for i from 2 to nF
        Draw line: time#[i-1], gHdB#[i-1], time#[i], gHdB#[i]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain (dB)"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Dynamic EQ Gains | low = red | mid = green | high = blue"

    # === Output waveform display (mono copy only for drawing) ===
    selectObject: outS
    if nch > 1
        disp = Convert to mono
    else
        disp = Copy: "PCA_display"
    endif

    Select outer viewport: 0, 8, 4.25, 5.78
    Select inner viewport: 0.60, 7.70, 4.44, 5.56
    selectObject: disp
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Processed Output | " + string$(nch) + " channel(s) preserved | peak " + fixed$(outPeakFinal, 3)
    removeObject: disp

    # === Summary strip ===
    Select outer viewport: 0, 8, 5.98, 6.85
    Select inner viewport: 0.60, 7.70, 6.06, 6.77
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizOrigName$ + " | " + string$(nch) + " channel(s) | formant-valid frames " + fixed$(100 * fmtFrac, 1) + "\% "
    summary2$ = "##Analysis##  formant PCA " + formantState$ + " | smoothing " + fixed$(control_smoothing_ms, 0) + " ms | frame step " + fixed$(frame_step_seconds * 1000, 1) + " ms"
    summary3$ = "##EQ & Output##  crossovers " + fixed$(low_hi_crossover1_hz, 0) + " / " + fixed$(low_hi_crossover2_hz, 0) + " Hz | high top " + fixed$(high_band_top_hz, 0) + " Hz | " + levelMode$ + " | peak " + fixed$(outPeakFinal, 3)
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore the complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
endif

# cleanup analysis and band intermediates
removeObject: snd, pit, inten, hnr, formantPath, formantObj
removeObject: feat, zfeat, pca, config, scr
removeObject: lowTier, midTier, highTier
removeObject: lowB, midB, highB, resB, midG, highG

label FINAL_RETURN
if play_result
    selectObject: outS
    Play
endif
selectObject: outS
