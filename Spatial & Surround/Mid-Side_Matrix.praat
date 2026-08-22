# ============================================================
# Praat AudioTools - Mid-Side_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# Version: 1.3.1 (2026)
# v1.3.1 (2026): VISUALIZATION LAYOUT FIX - separate header bands and compact Summary; DSP unchanged.
# v1.3 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
#
# Description:
#   Mid-Side Matrix - Encode, Decode & Spatial Stem Preparation.
#
#   A clean, REVERSIBLE Mid/Side matrix. Unlike the library's other
#   M/S uses (panning, mic simulation, subharmonics), this is a
#   dedicated stem tool: it splits a stereo mix into independent Mid
#   and Side objects, rebuilds L/R from them, verifies the matrix is
#   verifies losslessness within floating-point tolerance, and can prepare an anti-phase Side
#   pair for ambisonic spatialization.
#
#   Matrix (half-sum / unity-mono, safe for headroom):
#     M = (L + R) / 2      L = M + S
#     S = (L - R) / 2      R = M - S
#   L=R  -> M=L, S=0 ;  L=-R -> M=0, S=L ;  and reconstruction is exact.
#
#   The exact modes apply NOTHING but the linear matrix: no per-stem
#   normalization, no DC removal, no filtering, no resampling. Sample
#   count, rate, start time and duration are preserved so the round
#   trip is sample-reconstructible to floating-point precision
#   (lossless within floating-point rounding).
#
# Modes:
#   1. Stereo L/R -> Mid/Side      (one stereo Sound -> _Mid, _Side)
#   2. Mid/Side -> Stereo L/R      (two mono Sounds  -> _Stereo)
#   3. Round-trip verification     (encode, decode, null test)
#   4. Spatial source preparation  (Mid, Side_Left=+S, Side_Right=-S)
#
# Changelog v1.3:
#   Library-hardening (safety + reporting; DSP unchanged).
#   - Decode mode FAILS CLOSED if _Mid/_Side can't be identified (no more
#     guessing a polarity), and requires both stems to share a base name
#     (guards against mixing stems from different sources).
#   - Correlation bar is drawn N/A (grey) when undefined instead of 0.5.
#   - Wording: "uncorrelated" -> "anti-phase (L=-R)"; "nearly mono" now
#     requires low Side energy too (else "highly correlated / mono-
#     compatible"); "loss-free" -> "within floating-point tolerance".
#   - Form text: "select matching _Mid and _Side mono Sounds".
#
# Changelog v1.1:
#   Reporting/UX fixes.
#   - Side/Mid dB report now handles a silent Mid (anti-phase input
#     previously mislabelled "Side is silent" -- the opposite of reality).
#   - Decode mode identifies Mid/Side by _Mid/_Side name suffix instead of
#     trusting selection order (Praat returns Objects-list order, not click
#     order); falls back to order with a polarity warning.
#   - Play_result now plays a stereo preview reconstructed from Mid/Side,
#     not the untouched original.
#   - Decode mode reports the decoded peak and warns if it exceeds +/-1.
#   - Correlation clamped to [-1,1] and reported "undefined" when a channel
#     is silent; relabelled zero-lag normalized correlation (not Pearson).
#   - "Estimated width" relabelled "Side energy share" with an interpretation.
#   - Decode output name strips the _Mid suffix (piece_Mid -> piece_Stereo).
#   - Softened the spatial-mode wording and the round-trip "bit-faithful"
#     claim; noted that visualization is drawn only in Stereo -> M/S modes.
#
# Changelog v1.0:
#   Initial version: 4 modes, input validation, reference self-test
#   (mono / anti-phase / left-only / right-only), reconstruction null
#   test, width/mono-compatibility report, house-style visualization.
# ============================================================

form Mid-Side Matrix v1.3.1
    comment ── Mode ──
    optionmenu Mode: 1
        option Stereo L/R -> Mid/Side (select 1 stereo Sound)
        option Mid/Side -> Stereo L/R (select matching _Mid and _Side mono Sounds)
        option Round-trip verification (select 1 stereo Sound)
        option Spatial source preparation (select 1 stereo Sound)
    comment ─────────────────────────────────────────
    boolean Run_reference_test 1
    boolean Draw_visualization 1
    boolean Play_result 0
endform

clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  Mid-Side Matrix v1.3.1"
appendInfoLine: "=============================================="

# Capture the user's selection NOW, before the reference self-test runs.
# The self-test creates and removes objects, which clears the current
# selection; we restore it just before the mode dispatch.
numInputSel = numberOfSelected("Sound")
for i to numInputSel
    inputSel[i] = selected("Sound", i)
endfor

# ============================================================
# REFERENCE SELF-TEST (exercises the real Praat matrix code)
# ============================================================
# Builds a known 2-channel signal, runs it through the encode matrix,
# and checks Mid/Side against the analytic result. Catches polarity and
# scaling errors immediately.
if run_reference_test
    appendInfoLine: ""
    appendInfoLine: "Reference self-test:"
    refFail = 0
    @refTest: "mono (L=R)",        0.6,  0.6,  0.6,  0.0
    @refTest: "anti-phase (L=-R)", 0.6, -0.6,  0.0,  0.6
    @refTest: "left only (R=0)",   0.6,  0.0,  0.3,  0.3
    @refTest: "right only (L=0)",  0.0,  0.6,  0.3, -0.3
    if refFail = 0
        appendInfoLine: "  Self-test: PASS"
    else
        appendInfoLine: "  Self-test: ", refFail, " FAILURE(S)"
        exitScript: "Mid-Side matrix self-test failed. Aborting so no wrong stems are produced."
    endif
endif

# ============================================================
# MODE DISPATCH
# ============================================================

# Restore the user's original selection (the self-test above changed it).
if numInputSel >= 1
    selectObject: inputSel[1]
    for i from 2 to numInputSel
        plusObject: inputSel[i]
    endfor
endif

if mode = 2
    # -------- Mid/Side -> Stereo L/R --------
    numSel = numberOfSelected("Sound")
    if numSel <> 2
        exitScript: "Mode 2 needs exactly 2 mono Sounds selected (a _Mid and a _Side). Selected: " + string$(numSel)
    endif
    o1 = selected("Sound", 1)
    o2 = selected("Sound", 2)
    selectObject: o1
    n1$ = selected$("Sound")
    selectObject: o2
    n2$ = selected$("Sound")

    # Identify Mid/Side by name suffix (Praat returns them in Objects-list
    # order, NOT click order). For a tool meant to be exact and reversible we
    # FAIL CLOSED rather than guess a polarity.
    if endsWith(n1$, "_Mid") and endsWith(n2$, "_Side")
        midIn = o1
        sideIn = o2
    elsif endsWith(n1$, "_Side") and endsWith(n2$, "_Mid")
        midIn = o2
        sideIn = o1
    else
        exitScript: "Could not identify Mid and Side. Rename the two mono objects with matching _Mid and _Side suffixes (same base name) and run again."
    endif

    # Both must share the same base name (guard against mixing stems from
    # different sources, e.g. pieceA_Mid + pieceB_Side).
    selectObject: midIn
    mName$ = selected$("Sound")
    selectObject: sideIn
    sName$ = selected$("Sound")
    midBase$ = left$(mName$, length(mName$) - 4)
    sideBase$ = left$(sName$, length(sName$) - 5)
    if midBase$ <> sideBase$
        exitScript: "Mid and Side look like different sources ('" + midBase$ + "' vs '" + sideBase$ + "'). Select a matching _Mid / _Side pair."
    endif
    baseName$ = midBase$

    selectObject: midIn
    mCh = Get number of channels
    mSr = Get sampling frequency
    mSamp = Get number of samples
    mStart = Get start time
    selectObject: sideIn
    sCh = Get number of channels
    sSr = Get sampling frequency
    sSamp = Get number of samples
    sStart = Get start time

    if mCh <> 1 or sCh <> 1
        exitScript: "Both inputs must be mono (Mid and Side)."
    endif
    if mSr <> sSr
        exitScript: "Sample-rate mismatch between Mid and Side."
    endif
    if mSamp <> sSamp
        exitScript: "Length mismatch between Mid and Side."
    endif
    if abs(mStart - sStart) > 1e-9
        exitScript: "Start-time mismatch between Mid and Side."
    endif

    # L = M + S ; R = M - S
    selectObject: midIn
    lSound = Copy: "tmp_L"
    Formula: "Object_" + string$(midIn) + "[col] + Object_" + string$(sideIn) + "[col]"
    selectObject: midIn
    rSound = Copy: "tmp_R"
    Formula: "Object_" + string$(midIn) + "[col] - Object_" + string$(sideIn) + "[col]"

    selectObject: lSound
    plusObject: rSound
    stereoOut = Combine to stereo
    Rename: baseName$ + "_Stereo"
    removeObject: lSound, rSound

    # Peak check: L=M+S can exceed +/-1 without any error inside Praat, but will
    # clip on integer WAV export. Do NOT normalize (breaks the exact matrix);
    # reduce Mid and Side JOINTLY instead.
    selectObject: stereoOut
    decPeak = Get absolute extremum: 0, 0, "None"

    appendInfoLine: ""
    appendInfoLine: "Decoded stereo: ", selected$("Sound")
    appendInfoLine: "  ", mSamp, " samples @ ", mSr, " Hz"
    appendInfoLine: "  Decoded peak: ", fixed$(decPeak, 4)
    if decPeak > 1.0
        appendInfoLine: "  WARNING: output exceeds +/-1. Reduce Mid and Side JOINTLY"
        appendInfoLine: "           (same factor) before WAV export; do not normalize separately."
    endif
    if draw_visualization
        appendInfoLine: "  (Visualization is drawn only in the Stereo -> Mid/Side modes.)"
    endif

    if play_result
        selectObject: stereoOut
        Play
    endif
    selectObject: stereoOut
endif

if mode <> 2

# -------- Modes 1, 3, 4 all start from one stereo Sound --------
numSel = numberOfSelected("Sound")
if numSel <> 1
    exitScript: "Select exactly ONE stereo Sound. Selected: " + string$(numSel)
endif
original = selected("Sound")
selectObject: original
name$ = selected$("Sound")
nCh = Get number of channels
sr = Get sampling frequency
numSamples = Get number of samples
duration = Get total duration
startTime = Get start time

if nCh <> 2
    exitScript: "Input must be a 2-channel (stereo) Sound. Channels: " + string$(nCh)
endif
if numSamples < 2
    exitScript: "Input too short (need at least 2 samples)."
endif

appendInfoLine: ""
appendInfoLine: "Input: ", name$
appendInfoLine: "  Duration: ", fixed$(duration, 4), " s"
appendInfoLine: "  Sample rate: ", sr, " Hz"
appendInfoLine: "  Samples: ", numSamples

# ── Encode: extract channels, apply the matrix (original left untouched) ──
selectObject: original
lCh = Extract one channel: 1
selectObject: original
rCh = Extract one channel: 2

selectObject: lCh
midSound = Copy: name$ + "_Mid"
Formula: "(Object_" + string$(lCh) + "[col] + Object_" + string$(rCh) + "[col]) / 2"

selectObject: lCh
sideSound = Copy: name$ + "_Side"
Formula: "(Object_" + string$(lCh) + "[col] - Object_" + string$(rCh) + "[col]) / 2"

# ── Metrics ──
selectObject: lCh
rmsL = Get root-mean-square: 0, 0
selectObject: rCh
rmsR = Get root-mean-square: 0, 0
selectObject: midSound
midRms = Get root-mean-square: 0, 0
selectObject: sideSound
sideRms = Get root-mean-square: 0, 0

# Stereo correlation = mean(L*R) / (rmsL * rmsR)
selectObject: lCh
prodSound = Copy: "tmp_prod"
Formula: "self * Object_" + string$(rCh) + "[col]"
meanLR = Get mean: 0, 0
removeObject: prodSound
# Stereo correlation = mean(L*R) / (rms(L)*rms(R)). This is the standard
# zero-lag normalized channel correlation, NOT full Pearson (channel means are
# not subtracted -- negligible for audio with no DC). Undefined if a channel is
# silent (denominator zero).
corrDefined = 0
corr = 0
if rmsL > 1e-12 and rmsR > 1e-12
    corr = meanLR / (rmsL * rmsR)
    corr = min(1, max(-1, corr))
    corrDefined = 1
endif
if corrDefined
    corrStr$ = fixed$(corr, 4)
else
    corrStr$ = "undefined (a channel is silent)"
endif

# Side energy share: 0% = mono, 50% = uncorrelated equal energy,
# >50% = negative correlation, 100% = perfect anti-phase.
midEnergy = midRms * midRms
sideEnergy = sideRms * sideRms
sideShare = 0
if (midEnergy + sideEnergy) > 1e-18
    sideShare = 100 * sideEnergy / (midEnergy + sideEnergy)
endif

midSilent = 0
if midRms < 1e-9
    midSilent = 1
endif
sideSilent = 0
if sideRms < 1e-9
    sideSilent = 1
endif
sideMid_dB = 0
if midSilent and sideSilent
    sideMidStr$ = "n/a (input silent)"
elsif midSilent
    sideMidStr$ = "+inf dB (Mid silent -- fully anti-phase, L=-R)"
elsif sideSilent
    sideMidStr$ = "-inf dB (Side silent -- signal is mono)"
else
    sideMid_dB = 20 * log10(sideRms / midRms)
    sideMidStr$ = fixed$(sideMid_dB, 2) + " dB"
endif

# ── Reconstruction null test (encode -> decode -> subtract) ──
selectObject: midSound
recL = Copy: "tmp_recL"
Formula: "Object_" + string$(midSound) + "[col] + Object_" + string$(sideSound) + "[col]"
Formula: "self - Object_" + string$(lCh) + "[col]"
maxResL = Get absolute extremum: 0, 0, "None"
rmsResL = Get root-mean-square: 0, 0

selectObject: midSound
recR = Copy: "tmp_recR"
Formula: "Object_" + string$(midSound) + "[col] - Object_" + string$(sideSound) + "[col]"
Formula: "self - Object_" + string$(rCh) + "[col]"
maxResR = Get absolute extremum: 0, 0, "None"
rmsResR = Get root-mean-square: 0, 0
removeObject: recL, recR

maxResidual = maxResL
if maxResR > maxResidual
    maxResidual = maxResR
endif
rmsResidual = sqrt((rmsResL * rmsResL + rmsResR * rmsResR) / 2)

reconOK = 0
if maxResidual < 1e-9
    reconOK = 1
endif

# ============================================================
# REPORT
# ============================================================
appendInfoLine: ""
appendInfoLine: "Mid RMS:  ", fixed$(midRms, 6)
appendInfoLine: "Side RMS: ", fixed$(sideRms, 6)
appendInfoLine: "Side/Mid: ", sideMidStr$
appendInfoLine: "Channel correlation (zero-lag): ", corrStr$
appendInfoLine: "Side energy share: ", fixed$(sideShare, 1), " %"
if not corrDefined
    appendInfoLine: "  -> one or both channels silent"
elsif corr > 0.98 and sideShare < 2
    appendInfoLine: "  -> nearly mono"
elsif corr > 0.98
    appendInfoLine: "  -> highly correlated / mono-compatible (but level-imbalanced, so not mono)"
elsif sideShare > 50
    appendInfoLine: "  -> negative correlation / anti-phase (check mono compatibility)"
elsif sideShare > 30
    appendInfoLine: "  -> moderately wide"
endif
appendInfoLine: ""
appendInfoLine: "Reconstruction null test:"
appendInfoLine: "  Max residual: ", fixed$(maxResidual, 12)
appendInfoLine: "  RMS residual: ", fixed$(rmsResidual, 12)
if reconOK
    appendInfoLine: "  Status: PASS (reconstruction within floating-point tolerance)"
else
    appendInfoLine: "  Status: FAIL (residual too large)"
endif

# ============================================================
# MODE-SPECIFIC OUTPUT
# ============================================================
sideLeft = 0
sideRight = 0
if mode = 4
    # Spatial preparation: Mid, Side_Left = +S, Side_Right = -S.
    selectObject: sideSound
    sideLeft = Copy: name$ + "_Side_Left"
    selectObject: sideSound
    sideRight = Copy: name$ + "_Side_Right"
    Formula: "self * -1"
    appendInfoLine: ""
    appendInfoLine: "Spatial stems (all mono, ", numSamples, " samples):"
    appendInfoLine: "  ", name$, "_Mid         (anchor layer)"
    appendInfoLine: "  ", name$, "_Side_Left   (+S -> left trajectory)"
    appendInfoLine: "  ", name$, "_Side_Right  (-S -> right/mirror trajectory)"
    appendInfoLine: "  Note: process +S and -S symmetrically to preserve their"
    appendInfoLine: "        complementary polarity relationship. This does NOT guarantee"
    appendInfoLine: "        exact reconstruction of the original stereo image after"
    appendInfoLine: "        spatial encoding/decoding -- mode 4 is preparation for creative"
    appendInfoLine: "        spatial interpretation, not transparent stereo->ambisonics conversion."
elsif mode = 3
    appendInfoLine: ""
    if reconOK
        appendInfoLine: "Round-trip verified within numerical tolerance."
    else
        appendInfoLine: "Round-trip WARNING: reconstruction residual is not negligible."
    endif
    appendInfoLine: "Produced stems: ", name$, "_Mid, ", name$, "_Side"
else
    appendInfoLine: ""
    appendInfoLine: "Produced stems: ", name$, "_Mid, ", name$, "_Side"
endif

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Font size: 10
    Line width: 1

    # ---- Title ----
    Select outer viewport: 0, 8, 0, 0.30
    Select inner viewport: 0.60, 7.70, 0.02, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "{0.15, 0.15, 0.25}"
    Text: 0.5, "centre", 0.5, "half", "##MID-SIDE MATRIX v1.3.1##"
    Select outer viewport: 0, 8, 0.30, 0.52
    Select inner viewport: 0.60, 7.70, 0.31, 0.51
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.40, 0.40, 0.45}"
    Text: 0.5, "centre", 0.5, "half", name$ + "   |   " + fixed$(duration, 2) + " s   |   " + string$(sr) + " Hz"

    # Peaks for consistent amplitude scaling
    selectObject: lCh
    pkL = Get absolute extremum: 0, 0, "None"
    selectObject: rCh
    pkR = Get absolute extremum: 0, 0, "None"
    ampMax = pkL
    if pkR > ampMax
        ampMax = pkR
    endif
    if ampMax < 0.001
        ampMax = 0.001
    endif
    ampMax = ampMax * 1.15

    # ---- Panel 1: L / R input ----
    Select outer viewport: 0, 8, 0.72, 2.6
    Select inner viewport: 0.6, 7.7, 0.8, 2.55
    Axes: 0, duration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, duration, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.82}"
    Draw line: 0, 0, duration, 0
    selectObject: lCh
    Colour: "{0.20, 0.45, 0.75}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    selectObject: rCh
    Colour: "{0.85, 0.35, 0.30}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 0.72, 2.6
    Select inner viewport: 0.08, 0.52, 0.74, 2.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "L / R"
    Select outer viewport: 0, 8, 0.72, 2.6
    Select inner viewport: 0.6, 7.7, 0.8, 2.55
    Axes: 0, duration, -ampMax, ampMax
    Text top: "no", "Input stereo (blue = L, red = R)"

    # ---- Panel 2: Mid / Side ----
    Select outer viewport: 0, 8, 2.62, 4.5
    Select inner viewport: 0.6, 7.7, 2.7, 4.45
    Axes: 0, duration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, duration, -ampMax, ampMax
    Colour: "{0.80, 0.82, 0.80}"
    Draw line: 0, 0, duration, 0
    selectObject: midSound
    Colour: "{0.20, 0.55, 0.35}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    selectObject: sideSound
    Colour: "{0.75, 0.55, 0.15}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 2.62, 4.5
    Select inner viewport: 0.08, 0.52, 2.64, 4.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "M / S"
    Select outer viewport: 0, 8, 2.62, 4.5
    Select inner viewport: 0.6, 7.7, 2.7, 4.45
    Axes: 0, duration, -ampMax, ampMax
    Text top: "no", "Mid (green) / Side (amber)"

    # ---- Panel 3: width/correlation bars ----
    Select outer viewport: 0, 8, 4.52, 6.0
    Select inner viewport: 0.6, 7.7, 4.7, 5.85
    Axes: 0, 3, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 3, 0, 1
    # Mid vs Side energy share
    Paint rectangle: "{0.20, 0.55, 0.35}", 0.3, 0.9, 0, midEnergy / (midEnergy + sideEnergy + 1e-18)
    Paint rectangle: "{0.75, 0.55, 0.15}", 1.1, 1.7, 0, sideEnergy / (midEnergy + sideEnergy + 1e-18)
    # correlation mapped 0..1 (from -1..1); drawn only when defined
    if corrDefined
        corrBar = (corr + 1) / 2
        Paint rectangle: "{0.30, 0.45, 0.70}", 1.9, 2.7, 0, corrBar
    else
        Paint rectangle: "{0.85, 0.85, 0.85}", 1.9, 2.7, 0, 1
        Colour: "{0.40, 0.40, 0.40}"
        Text: 2.3, "centre", 0.5, "half", "N/A"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text: 0.6, "centre", -0.08, "half", "Mid E"
    Text: 1.4, "centre", -0.08, "half", "Side E"
    Text: 2.3, "centre", -0.08, "half", "corr"
    Font size: 7
    Text top: "no", "Energy share and correlation"

    # ---- Panel 4: summary (grey) ----
    Select outer viewport: 0, 8, 6.02, 7.5
    Select inner viewport: 0.6, 7.7, 6.15, 7.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.15, 0.15, 0.15}"
    Font size: 7
    Text: 0.04, "left", 0.84, "half", "##Summary##"
    Font size: 6
    Text: 0.04, "left", 0.60, "half", "Mid RMS " + fixed$(midRms, 4) + "  |  Side RMS " + fixed$(sideRms, 4) + "  |  Side/Mid " + sideMidStr$
    Text: 0.04, "left", 0.37, "half", "Correlation " + corrStr$ + "  |  Side energy share " + fixed$(sideShare, 1) + " \%"
    reconLabel$ = "FAIL"
    if reconOK
        reconLabel$ = "PASS"
    endif
    Text: 0.04, "left", 0.13, "half", "Reconstruction max " + fixed$(maxResidual, 10) + "  rms " + fixed$(rmsResidual, 10) + "  |  Null test " + reconLabel$ + "  |  M=(L+R)/2  S=(L-R)/2"
    Select inner viewport: 0.6, 7.7, 6.15, 7.4
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
endif

# ============================================================
Select outer viewport: 0, 8, 0, 7.60
Font size: 10
Colour: "Black"
Line width: 1
Solid line
# CLEANUP + FINAL SELECTION
# ============================================================
removeObject: lCh, rCh

if play_result
    # Play a stereo preview reconstructed from Mid/Side (L=M+S, R=M-S), i.e.
    # what the stems sound like recombined -- not the untouched original.
    selectObject: midSound
    prevL = Copy: "tmp_prevL"
    Formula: "self + Object_" + string$(sideSound) + "[col]"
    selectObject: midSound
    prevR = Copy: "tmp_prevR"
    Formula: "self - Object_" + string$(sideSound) + "[col]"
    selectObject: prevL
    plusObject: prevR
    prevStereo = Combine to stereo
    Play
    removeObject: prevStereo, prevL, prevR
endif

# Select the produced stems as the result.
if mode = 4
    removeObject: sideSound
    selectObject: midSound
    plusObject: sideLeft
    plusObject: sideRight
else
    selectObject: midSound
    plusObject: sideSound
endif

endif

# ============================================================
# PROCEDURES
# ============================================================

# Build a known 2-channel signal, run the encode matrix, and check Mid/Side.
procedure refTest: .label$, .lval, .rval, .expM, .expS
    .snd = Create Sound from formula: "mstest", 2, 0, 0.001, 44100,
        ... "if row = 1 then " + string$(.lval) + " else " + string$(.rval) + " fi"
    .l = Extract one channel: 1
    selectObject: .snd
    .r = Extract one channel: 2
    selectObject: .l
    .m = Copy: "mstest_M"
    Formula: "(Object_" + string$(.l) + "[col] + Object_" + string$(.r) + "[col]) / 2"
    .gotM = Get value at sample number: 1, 1
    selectObject: .l
    .s = Copy: "mstest_S"
    Formula: "(Object_" + string$(.l) + "[col] - Object_" + string$(.r) + "[col]) / 2"
    .gotS = Get value at sample number: 1, 1
    removeObject: .snd, .l, .r, .m, .s
    if abs(.gotM - .expM) < 1e-9 and abs(.gotS - .expS) < 1e-9
        appendInfoLine: "  [PASS] ", .label$, ": M=", fixed$(.gotM, 3), " S=", fixed$(.gotS, 3)
    else
        appendInfoLine: "  [FAIL] ", .label$, ": M=", fixed$(.gotM, 3), " S=", fixed$(.gotS, 3),
            ... " (expected M=", fixed$(.expM, 3), " S=", fixed$(.expS, 3), ")"
        refFail = refFail + 1
    endif
endproc
