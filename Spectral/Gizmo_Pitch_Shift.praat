# ============================================================
# Praat AudioTools - Gizmo_Pitch_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2026) - Vectorised phase vocoder, presets, visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#   Requires Praat 6.1+ (vector syntax). Target: 6.4.42.
#
####################################################################
# INPUT VALIDATION
####################################################################

numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound_original = selected("Sound")
sound_name$ = selected$("Sound")

####################################################################
# FORM
####################################################################

form Gizmo Pitch Shift v1.0
    optionmenu Preset 1
        option Custom
        option Fifth up (+7 st, 80 ms)
        option Octave up (+12 st, 40 ms)
        option Octave down (-12 st, 120 ms)
        option Minor third up (+3 st, Hamming)
        option Detune shimmer (+0.2 st, 50% wet)
        option Smeared drone (-5 st, Gaussian 250 ms)
        option Transient safe (+7 st, 23 ms, 87.5% overlap)
    real Semitones 7.0
    real Frame_length_s 0.08
    real Hop_fraction 0.25
    optionmenu Window_type 1
        option Hann
        option Hamming
        option Gaussian
    real Dry_wet_mix 1.0
    boolean Draw_visualization 1
    boolean Show_info 1
    boolean Play_result 1
endform

####################################################################
# APPLY PRESETS
####################################################################

if preset = 2
    # Fifth up - the reference setting
    semitones = 7.0
    frame_length_s = 0.08
    hop_fraction = 0.25
    window_type = 1
    dry_wet_mix = 1.0
    presetName$ = "FifthUp"
elsif preset = 3
    # Octave up - short frame keeps the upshifted transients tight
    semitones = 12.0
    frame_length_s = 0.04
    hop_fraction = 0.25
    window_type = 1
    dry_wet_mix = 1.0
    presetName$ = "OctaveUp"
elsif preset = 4
    # Octave down - long frame and fine hop; downshifting two source
    # bins onto one target needs the frequency resolution
    semitones = -12.0
    frame_length_s = 0.12
    hop_fraction = 0.125
    window_type = 1
    dry_wet_mix = 1.0
    presetName$ = "OctaveDown"
elsif preset = 5
    # Minor third up, Hamming - lower sidelobes, less taper
    semitones = 3.0
    frame_length_s = 0.08
    hop_fraction = 0.25
    window_type = 2
    dry_wet_mix = 1.0
    presetName$ = "MinorThirdUp"
elsif preset = 6
    # Detune shimmer - a fifth of a semitone against the dry signal
    semitones = 0.2
    frame_length_s = 0.06
    hop_fraction = 0.25
    window_type = 1
    dry_wet_mix = 0.5
    presetName$ = "DetuneShimmer"
elsif preset = 7
    # Smeared drone - long Gaussian frame, coarse hop. This is the
    # one preset that deliberately smears: 250 ms of time blur is
    # the character, not an artifact.
    semitones = -5.0
    frame_length_s = 0.25
    hop_fraction = 0.5
    window_type = 3
    dry_wet_mix = 1.0
    presetName$ = "SmearedDrone"
elsif preset = 8
    # Transient safe - short frame, 87.5% overlap
    semitones = 7.0
    frame_length_s = 0.023
    hop_fraction = 0.125
    window_type = 1
    dry_wet_mix = 1.0
    presetName$ = "TransientSafe"
else
    presetName$ = "Custom"
endif

####################################################################
# PARAMETER VALIDATION
####################################################################

warnLines$ = ""

if semitones < -12.0
    warnLines$ = warnLines$ + "  Semitones clamped from " + fixed$(semitones, 2) + " to -12." + newline$
    semitones = -12.0
endif
if semitones > 12.0
    warnLines$ = warnLines$ + "  Semitones clamped from " + fixed$(semitones, 2) + " to +12." + newline$
    semitones = 12.0
endif
if dry_wet_mix < 0.0
    warnLines$ = warnLines$ + "  Dry_wet_mix clamped to 0." + newline$
    dry_wet_mix = 0.0
endif
if dry_wet_mix > 1.0
    warnLines$ = warnLines$ + "  Dry_wet_mix clamped to 1." + newline$
    dry_wet_mix = 1.0
endif
if hop_fraction < 0.03125
    warnLines$ = warnLines$ + "  Hop_fraction clamped to 0.03125 (32x overlap)." + newline$
    hop_fraction = 0.03125
endif
if hop_fraction > 1.0
    warnLines$ = warnLines$ + "  Hop_fraction clamped to 1.0 (no overlap)." + newline$
    hop_fraction = 1.0
endif
if frame_length_s <= 0.0
    warnLines$ = warnLines$ + "  Frame_length_s was <= 0; reset to 0.08 s." + newline$
    frame_length_s = 0.08
endif

selectObject: sound_original
fs = Get sampling frequency
dt = Get sampling period
nSrc = Get number of samples
nCh = Get number of channels
xmin1 = Get start time
duration_s = Get total duration

####################################################################
# FFT GEOMETRY
####################################################################

ratio = 2 ^ (semitones / 12)

nGrainRaw = frame_length_s * fs
nGrain = 2 ^ round(log2(nGrainRaw))
if nGrain < 64
    nGrain = 64
endif
if nGrain > 32768
    nGrain = 32768
endif

nBins = nGrain / 2 + 1
nBinsM1 = nBins - 1
binWidth = fs / nGrain

hop = round(nGrain * hop_fraction)
if hop < 1
    hop = 1
endif
if hop > nGrain
    hop = nGrain
endif

# Expected phase advance per hop for bin k is expct * (k - 1)
expct = 2 * pi * hop / nGrain

padN = nGrain
nPad = nSrc + 2 * padN
nFrames = floor((nPad - nGrain) / hop) + 1

if nFrames < 1
    exitScript: "Sound is too short for a frame of " + string$(nGrain) + " samples."
endif

actualFrame_s = nGrain * dt
overlapPct = 100 * (1 - hop / nGrain)

# Lanes for the gather. Contributing source bins span a window of
# width 1/ratio, so this bound is exact for any ratio in [0.5, 2].
nLanes = ceiling(1 / ratio) + 2

# Highest source frequency that survives transposition
if ratio > 1
    survivingHz = (fs / 2) / ratio
else
    survivingHz = fs / 2
endif

if window_type = 1
    windowName$ = "Hann"
elsif window_type = 2
    windowName$ = "Hamming"
else
    windowName$ = "Gaussian"
endif

frameSnapRatio = actualFrame_s / frame_length_s
if frameSnapRatio > 1.25 or frameSnapRatio < 0.8
    warnLines$ = warnLines$ + "  Frame snapped from " + fixed$(frame_length_s * 1000, 1)
        ... + " ms to " + fixed$(actualFrame_s * 1000, 1) + " ms (power-of-two FFT)." + newline$
endif

####################################################################
# REPORT HEADER
####################################################################

writeInfoLine: "=== Gizmo Pitch Shift v1.0 ==="
appendInfoLine: "Input: ", sound_name$, "   ", fixed$(duration_s, 3), " s, ", nCh, " ch, ",
    ... fixed$(fs, 0), " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Transposition: ", fixed$(semitones, 2), " st   (ratio ", fixed$(ratio, 6), ")"
appendInfoLine: "FFT / frame:   ", nGrain, " samples = ", fixed$(actualFrame_s * 1000, 2),
    ... " ms (requested ", fixed$(frame_length_s * 1000, 2), " ms)"
appendInfoLine: "Bins:          ", nBins, "   bin width ", fixed$(binWidth, 3), " Hz"
appendInfoLine: "Hop:           ", hop, " samples = ", fixed$(hop * dt * 1000, 2), " ms   (",
    ... fixed$(overlapPct, 1), "% overlap)"
appendInfoLine: "Window:        ", windowName$, "   gather lanes ", nLanes
appendInfoLine: "Frames:        ", nFrames, " per channel"
appendInfoLine: ""

####################################################################
# ANALYSIS / SYNTHESIS WINDOW
#   One window Sound of nGrain samples, applied twice: once before
#   the FFT and once after resynthesis. The weight buffer therefore
#   accumulates w^2, and dividing by it gives unity gain regardless
#   of whether the window satisfies COLA at this hop.
####################################################################

if window_type = 1
    winFormula$ = "0.5 - 0.5 * cos (2 * pi * (col - 1) / 'nGrain:0')"
elsif window_type = 2
    winFormula$ = "0.54 - 0.46 * cos (2 * pi * (col - 1) / 'nGrain:0')"
else
    winFormula$ = "exp (-0.5 * ((col - 1 - ('nGrain:0' - 1) / 2) / (0.4 * ('nGrain:0' - 1) / 2)) ^ 2)"
endif

winId = Create Sound from formula: "gz_win", 1, 0, nGrain * dt, fs, winFormula$

####################################################################
# WEIGHT (COLA) BUFFER - audio independent, built once
####################################################################

wgtId = Create Sound from formula: "gz_wgt", 1, 0, nPad * dt, fs, "0"

for f from 1 to nFrames
    off = (f - 1) * hop
    # Sample i of a Sound starting at 0 sits at x = (i - 0.5) * dt.
    # The +/-0.25 sample margins bracket exactly samples
    # off+1 .. off+nGrain and nothing else.
    t1 = (off + 0.25) * dt
    t2 = (off + nGrain - 0.25) * dt
    selectObject: wgtId
    Formula (part): t1, t2, 1, 1, "self + object['winId:0', 1, col - 'off:0'] ^ 2"
endfor

selectObject: wgtId
wMax = Get maximum: padN * dt, (padN + nSrc) * dt, "None"
wMin = Get minimum: padN * dt, (padN + nSrc) * dt, "None"
if wMax <= 0
    exitScript: "Window and hop combination produced a zero weight buffer."
endif
colaRipplePct = 100 * (wMax - wMin) / wMax
wEps = 1e-6 * wMax

appendInfoLine: "COLA weight:   min ", fixed$(wMin, 6), "  max ", fixed$(wMax, 6),
    ... "  ripple ", fixed$(colaRipplePct, 4), "%"
appendInfoLine: ""
appendInfoLine: "Processing ", nCh, " channel(s) x ", nFrames, " frames..."

####################################################################
# OUTPUT CONTAINER (built at time 0, shifted back to xmin at the end)
####################################################################

output_sound = Create Sound from formula: "gz_out", nCh, 0, nSrc * dt, fs, "0"

####################################################################
# PER-CHANNEL PHASE VOCODER
####################################################################

specTgtId = 0

for ch from 1 to nCh

    selectObject: sound_original
    chanId = Extract one channel: ch

    # --- zero-padded input buffer -----------------------------------
    padId = Create Sound from formula: "gz_pad", 1, 0, nPad * dt, fs, "0"
    Formula: "if col > 'padN:0' and col <= 'padN:0' + 'nSrc:0' then object['chanId:0', 1, min ('nSrc:0', max (1, col - 'padN:0'))] else 0 fi"

    accId = Create Sound from formula: "gz_acc", 1, 0, nPad * dt, fs, "0"
    grainId = Create Sound from formula: "gz_grain", 1, 0, nGrain * dt, fs, "0"

    # --- per-bin buffers, all nBins samples wide --------------------
    #   polId    2 ch : row 1 = magnitude, row 2 = phase (this frame)
    #   prevPhId 1 ch : phase of the previous frame  (per SOURCE bin)
    #   advId    1 ch : true phase advance x ratio   (per SOURCE bin)
    #   synMagId 1 ch : accumulated magnitude        (per TARGET bin)
    #   synFrqId 1 ch : scaled advance               (per TARGET bin)
    #   sumPhId  1 ch : running synthesis phase      (per TARGET bin)
    polId = Create Sound from formula: "gz_pol", 2, 0, nBins * dt, fs, "0"
    prevPhId = Create Sound from formula: "gz_prevph", 1, 0, nBins * dt, fs, "0"
    advId = Create Sound from formula: "gz_adv", 1, 0, nBins * dt, fs, "0"
    synMagId = Create Sound from formula: "gz_synmag", 1, 0, nBins * dt, fs, "0"
    synFrqId = Create Sound from formula: "gz_synfrq", 1, 0, nBins * dt, fs, "0"
    sumPhId = Create Sound from formula: "gz_sumph", 1, 0, nBins * dt, fs, "0"

    for f from 1 to nFrames

        off = (f - 1) * hop

        # --- windowed grain -----------------------------------------
        selectObject: grainId
        Formula: "object['padId:0', 1, col + 'off:0'] * object['winId:0', 1, col]"

        # --- forward FFT --------------------------------------------
        specId = To Spectrum: "yes"

        # --- magnitude and phase, one vector pass -------------------
        selectObject: polId
        Formula: "if row = 1 then sqrt (object['specId:0', 1, col] ^ 2 + object['specId:0', 2, col] ^ 2) else arctan2 (object['specId:0', 2, col], object['specId:0', 1, col]) fi"

        # --- true phase advance, scaled by ratio --------------------
        #   trueAdv = (ph - pp) - 2*pi*round ((ph - pp - E) / (2*pi))
        #   with E = expct*(col-1). The E terms cancel outside the
        #   wrap, which is why this fits in one formula.
        selectObject: advId
        Formula: "'ratio:12' * ((object['polId:0', 2, col] - object['prevPhId:0', 1, col]) - 2 * pi * round ((object['polId:0', 2, col] - object['prevPhId:0', 1, col] - 'expct:12' * (col - 1)) / (2 * pi)))"

        # --- remember this frame's phase ----------------------------
        selectObject: prevPhId
        Formula: "object['polId:0', 2, col]"

        # --- bin transposition, as a masked gather ------------------
        selectObject: synMagId
        Formula: "0"
        selectObject: synFrqId
        Formula: "0"

        for lane from 0 to nLanes - 1
            # k0 = 0-based source bin for this lane and target col
            k0$ = "(floor ((col - 1.5) / 'ratio:12') + 'lane:0')"
            cond$ = k0$ + " >= 0 and " + k0$ + " <= 'nBinsM1:0' and round (" + k0$ + " * 'ratio:12') = col - 1"
            idx$ = "min ('nBins:0', max (1, " + k0$ + " + 1))"

            selectObject: synMagId
            Formula: "if " + cond$ + " then self + object['polId:0', 1, " + idx$ + "] else self fi"

            selectObject: synFrqId
            Formula: "if " + cond$ + " then object['advId:0', 1, " + idx$ + "] else self fi"
        endfor

        # --- integrate the synthesis phase --------------------------
        selectObject: sumPhId
        Formula: "self + object['synFrqId:0', 1, col]"

        # --- stamp the target spectrum ------------------------------
        #   The (col > 1) * (col < nBins) mask keeps DC and Nyquist
        #   purely real.
        if specTgtId = 0
            selectObject: specId
            specTgtId = Copy: "gz_tgt"
        endif

        selectObject: specTgtId
        Formula: "if row = 1 then object['synMagId:0', 1, col] * cos (object['sumPhId:0', 1, col]) else object['synMagId:0', 1, col] * sin (object['sumPhId:0', 1, col]) * (col > 1) * (col < 'nBins:0') fi"

        resynId = To Sound

        # --- overlap-add with the synthesis window ------------------
        t1 = (off + 0.25) * dt
        t2 = (off + nGrain - 0.25) * dt
        selectObject: accId
        Formula (part): t1, t2, 1, 1, "self + object['resynId:0', 1, col - 'off:0'] * object['winId:0', 1, col - 'off:0']"

        removeObject: specId, resynId
    endfor

    # --- COLA normalisation -----------------------------------------
    selectObject: accId
    Formula: "if object['wgtId:0', 1, col] > 'wEps' then self / object['wgtId:0', 1, col] else 0 fi"

    # --- copy the valid interior into the output channel -------------
    selectObject: output_sound
    Formula (part): 0, nSrc * dt, ch, ch, "object['accId:0', 1, col + 'padN:0']"

    removeObject: chanId, padId, accId, grainId
    removeObject: polId, prevPhId, advId, synMagId, synFrqId, sumPhId

    appendInfoLine: "  channel ", ch, " done"
endfor

if specTgtId <> 0
    removeObject: specTgtId
endif
removeObject: winId

####################################################################
# DRY / WET
#   The pipeline is latency-free (the analysis pad is removed again
#   when the interior is copied out), so the dry path is sample
#   aligned with the wet path.
####################################################################

if dry_wet_mix < 1.0
    selectObject: output_sound
    Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * object['sound_original:0', row, col]"
endif

####################################################################
# TIME DOMAIN AND NAMING
####################################################################

selectObject: output_sound
if xmin1 <> 0
    Shift times by: xmin1
endif

if semitones = round(semitones)
    stTag$ = fixed$(abs(semitones), 0)
else
    stTag$ = fixed$(abs(semitones), 2)
endif
if semitones < 0
    signTag$ = "-"
else
    signTag$ = "+"
endif

output_name$ = sound_name$ + "_gizmo_shift_" + signTag$ + stTag$ + "st"
Rename: output_name$

peakOut = Get absolute extremum: 0, 0, "None"

selectObject: sound_original
peakIn = Get absolute extremum: 0, 0, "None"

if peakOut > 1.0
    warnLines$ = warnLines$ + "  Output peak " + fixed$(peakOut, 4)
        ... + " exceeds +/-1.0. No normalization is applied by design." + newline$
endif

####################################################################
# MEASUREMENT (for the report and the visualization)
####################################################################

if nCh > 1
    selectObject: sound_original
    monoInId = Convert to mono
    selectObject: output_sound
    monoOutId = Convert to mono
else
    selectObject: sound_original
    monoInId = Copy: "gz_monoin"
    selectObject: output_sound
    monoOutId = Copy: "gz_monoout"
endif

# --- band energies, shared reference so level differences show ------
nBands = 44
loFreq = 40
hiFreq = fs / 2
logLo = log10(loFreq)
logHi = log10(hiFreq)

bandLo# = zero#(nBands)
bandHi# = zero#(nBands)
bandCtr# = zero#(nBands)
bandIn# = zero#(nBands)
bandOut# = zero#(nBands)
bandIndB# = zero#(nBands)
bandOutdB# = zero#(nBands)

for b to nBands
    bandLo#[b] = 10 ^ (logLo + (logHi - logLo) * (b - 1) / nBands)
    bandHi#[b] = 10 ^ (logLo + (logHi - logLo) * b / nBands)
    bandCtr#[b] = sqrt(bandLo#[b] * bandHi#[b])
endfor

selectObject: monoInId
specInId = To Spectrum: "yes"
for b to nBands
    bandIn#[b] = Get band energy: bandLo#[b], bandHi#[b]
endfor

selectObject: monoOutId
specOutId = To Spectrum: "yes"
for b to nBands
    bandOut#[b] = Get band energy: bandLo#[b], bandHi#[b]
endfor

removeObject: specInId, specOutId

refEnergy = 0
for b to nBands
    if bandIn#[b] > refEnergy
        refEnergy = bandIn#[b]
    endif
endfor
if refEnergy <= 0
    refEnergy = 1e-20
endif

for b to nBands
    bandIndB#[b] = 10 * log10((bandIn#[b] + 1e-20) / refEnergy)
    bandOutdB#[b] = 10 * log10((bandOut#[b] + 1e-20) / refEnergy)
endfor

# --- pitch verification ----------------------------------------------
pitchFloor = 60
pitchCeil = 1500
if pitchCeil > fs / 2 - 50
    pitchCeil = fs / 2 - 50
endif

pitchOk = 0
medIn = undefined
medOut = undefined
measuredSt = undefined
pitchInId = 0
pitchOutId = 0

if duration_s > 0.25
    pitchOk = 1
    selectObject: monoInId
    pitchInId = To Pitch: 0.0, pitchFloor, pitchCeil
    medIn = Get quantile: 0, 0, 0.5, "Hertz"
    selectObject: monoOutId
    pitchOutId = To Pitch: 0.0, pitchFloor, pitchCeil
    medOut = Get quantile: 0, 0, 0.5, "Hertz"
    if medIn <> undefined and medOut <> undefined
        if medIn > 0 and medOut > 0
            measuredSt = 12 * log2(medOut / medIn)
        endif
    endif
endif

####################################################################
# VISUALIZATION
####################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    colIn$ = "{0.20, 0.40, 0.80}"
    colOut$ = "{0.80, 0.20, 0.40}"
    colAcc$ = "{0.20, 0.65, 0.35}"
    colGrey$ = "{0.97, 0.97, 0.97}"
    colFaint$ = "{0.88, 0.88, 0.88}"
    colLabel$ = "{0.45, 0.45, 0.45}"

    wvSlices = 260

    # === TITLE ======================================================
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", -1.7, "half", "##Gizmo Pitch Shift v1.0##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
        ... sound_name$ + " | " + presetName$
        ... + " | " + fixed$(semitones, 2) + " st (ratio " + fixed$(ratio, 4) + ")"
        ... + " | FFT " + string$(nGrain)
        ... + " | hop " + string$(hop)
        ... + " | " + windowName$
        ... + " | wet " + fixed$(dry_wet_mix, 2)

    # === PANEL: INPUT WAVEFORM ======================================
    Select outer viewport: 0, 4, 0.50, 1.85
    Select inner viewport: 0.6, 3.85, 0.60, 1.80

    wvYIn = peakIn
    if wvYIn <= 0
        wvYIn = 1
    endif
    wvYIn = wvYIn * 1.1

    Axes: 0, duration_s, -wvYIn, wvYIn
    Paint rectangle: colGrey$, 0, duration_s, -wvYIn, wvYIn
    Colour: colFaint$
    Draw line: 0, 0, duration_s, 0

    Colour: colIn$
    for s to wvSlices
        sliceT1 = xmin1 + duration_s * (s - 1) / wvSlices
        sliceT2 = xmin1 + duration_s * s / wvSlices
        selectObject: monoInId
        sMax = Get maximum: sliceT1, sliceT2, "None"
        sMin = Get minimum: sliceT1, sliceT2, "None"
        drawX = duration_s * (s - 0.5) / wvSlices
        Draw line: drawX, sMin, drawX, sMax
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, wvYIn / 2, "yes", "yes", "no"
    Marks bottom every: 1, duration_s / 4, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Amplitude"
    Text top: "no", "Input (peak " + fixed$(peakIn, 4) + ")"
    Text bottom: "yes", "Time (s)"

    # === PANEL: OUTPUT WAVEFORM =====================================
    Select outer viewport: 4, 8, 0.50, 1.85
    Select inner viewport: 4.2, 7.7, 0.60, 1.80

    wvYOut = peakOut
    if wvYOut <= 0
        wvYOut = 1
    endif
    wvYOut = wvYOut * 1.1

    Axes: 0, duration_s, -wvYOut, wvYOut
    Paint rectangle: colGrey$, 0, duration_s, -wvYOut, wvYOut
    Colour: colFaint$
    Draw line: 0, 0, duration_s, 0

    Colour: colOut$
    for s to wvSlices
        sliceT1 = xmin1 + duration_s * (s - 1) / wvSlices
        sliceT2 = xmin1 + duration_s * s / wvSlices
        selectObject: monoOutId
        sMax = Get maximum: sliceT1, sliceT2, "None"
        sMin = Get minimum: sliceT1, sliceT2, "None"
        drawX = duration_s * (s - 0.5) / wvSlices
        Draw line: drawX, sMin, drawX, sMax
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, wvYOut / 2, "yes", "yes", "no"
    Marks bottom every: 1, duration_s / 4, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Amplitude"
    Text top: "no", "Output (peak " + fixed$(peakOut, 4) + ", no normalization)"
    Text bottom: "yes", "Time (s)"

    # === PANEL: BIN TRANSPOSITION MAP ===============================
    #   The staircase IS the algorithm. Every flat tread is a target
    #   bin fed by two source bins (downshift), every jump of two is
    #   a target bin fed by none (upshift). Distance from the
    #   diagonal is the quantization error the phase accumulator has
    #   to absorb.
    Select outer viewport: 0, 4, 1.90, 3.60
    Select inner viewport: 0.8, 3.85, 2.00, 3.55

    mapShown = 28
    if mapShown > nBinsM1
        mapShown = nBinsM1
    endif
    mapYMax = round(mapShown * ratio) + 2
    if mapYMax < mapShown
        mapYMax = mapShown
    endif

    Axes: 0, mapShown, 0, mapYMax
    Paint rectangle: colGrey$, 0, mapShown, 0, mapYMax

    Colour: colFaint$
    Draw line: 0, 0, mapShown, mapShown

    Colour: colIn$
    Line width: 1.5
    for k0 from 0 to mapShown - 1
        kt = round(k0 * ratio)
        ktNext = round((k0 + 1) * ratio)
        if kt <= mapYMax
            Draw line: k0, kt, k0 + 1, kt
            if ktNext <= mapYMax
                Draw line: k0 + 1, kt, k0 + 1, ktNext
            endif
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Marks left every: 1, ceiling(mapYMax / 6), "yes", "yes", "no"
    Marks bottom every: 1, ceiling(mapShown / 7), "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Target bin"
    Text top: "no", "Bin map k -> round(k x " + fixed$(ratio, 4) + "), first " + string$(mapShown) + " bins"
    Text bottom: "yes", "Source bin"
    Font size: 6
    Colour: colLabel$
    Text: mapShown * 0.03, "left", mapYMax * 0.94, "half", "grey = identity"
    if ratio > 1
        Colour: colOut$
        Text: mapShown * 0.03, "left", mapYMax * 0.86, "half",
            ... "source above " + fixed$(survivingHz, 0) + " Hz discarded"
    endif

    # === PANEL: SPECTRUM IN vs OUT ==================================
    Select outer viewport: 4, 8, 1.90, 3.60
    Select inner viewport: 4.35, 7.7, 2.00, 3.55

    specDbMin = -70
    specDbMax = 6
    Axes: logLo, logHi, specDbMin, specDbMax
    Paint rectangle: colGrey$, logLo, logHi, specDbMin, specDbMax

    Colour: colFaint$
    gridDb = -60
    while gridDb < specDbMax
        Draw line: logLo, gridDb, logHi, gridDb
        gridDb = gridDb + 20
    endwhile

    if ratio > 1 and survivingHz > loFreq
        Colour: "{0.85, 0.75, 0.75}"
        Draw line: log10(survivingHz), specDbMin, log10(survivingHz), specDbMax
    endif

    Colour: colIn$
    Line width: 1.5
    for b from 1 to nBands - 1
        y1 = bandIndB#[b]
        y2 = bandIndB#[b + 1]
        if y1 < specDbMin
            y1 = specDbMin
        endif
        if y2 < specDbMin
            y2 = specDbMin
        endif
        Draw line: log10(bandCtr#[b]), y1, log10(bandCtr#[b + 1]), y2
    endfor

    Colour: colOut$
    for b from 1 to nBands - 1
        y1 = bandOutdB#[b]
        y2 = bandOutdB#[b + 1]
        if y1 < specDbMin
            y1 = specDbMin
        endif
        if y2 < specDbMin
            y2 = specDbMin
        endif
        Draw line: log10(bandCtr#[b]), y1, log10(bandCtr#[b + 1]), y2
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    Font size: 6
    decade = ceiling(logLo)
    while decade <= logHi
        One mark bottom: decade, "yes", "yes", "no", fixed$(10 ^ decade, 0)
        decade = decade + 1
    endwhile
    Font size: 7
    Text left: "yes", "Band energy (dB)"
    Text top: "no", "Spectrum, shared reference (no gain rescaling)"
    Text bottom: "yes", "Frequency (Hz, log)"
    Font size: 6
    Colour: colIn$
    Text: logLo + (logHi - logLo) * 0.02, "left", specDbMax - 5, "half", "input"
    Colour: colOut$
    Text: logLo + (logHi - logLo) * 0.02, "left", specDbMax - 11, "half", "output"

    # === PANEL: WINDOW OVERLAP AND ACCUMULATED ENVELOPE =============
    Select outer viewport: 0, 4, 3.65, 5.35
    Select inner viewport: 0.8, 3.85, 3.75, 5.30

    colaSpan = 4
    maxSpan = floor(nSrc / nGrain)
    if colaSpan > maxSpan
        colaSpan = maxSpan
    endif
    if colaSpan < 1
        colaSpan = 1
    endif

    Axes: 0, colaSpan, 0, 1.35
    Paint rectangle: colGrey$, 0, colaSpan, 0, 1.35
    Colour: colFaint$
    Draw line: 0, 1, colaSpan, 1

    # individual w^2 windows at the working hop
    hopFracDraw = hop / nGrain
    Colour: "{0.75, 0.80, 0.90}"
    startPos = -1
    while startPos < colaSpan
        prevY = 0
        for q from 0 to 40
            wx = q / 40
            if window_type = 1
                wv = 0.5 - 0.5 * cos(2 * pi * wx)
            elsif window_type = 2
                wv = 0.54 - 0.46 * cos(2 * pi * wx)
            else
                wv = exp(-0.5 * ((wx - 0.5) / 0.2) ^ 2)
            endif
            wv = wv * wv / wMax
            if q > 0
                Draw line: startPos + (q - 1) / 40, prevY, startPos + wx, wv
            endif
            prevY = wv
        endfor
        startPos = startPos + hopFracDraw
    endwhile

    # accumulated envelope, read from the real weight buffer
    Colour: colAcc$
    Line width: 1.5
    colaPts = 240
    colaBase = padN
    prevY = undefined
    for q from 0 to colaPts
        sampPos = round(colaBase + colaSpan * nGrain * q / colaPts)
        if sampPos < 1
            sampPos = 1
        endif
        if sampPos > nPad
            sampPos = nPad
        endif
        selectObject: wgtId
        wv = Get value at sample number: 1, sampPos
        wv = wv / wMax
        if q > 0
            Draw line: colaSpan * (q - 1) / colaPts, prevY, colaSpan * q / colaPts, wv
        endif
        prevY = wv
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "w^2 / max"
    Text top: "no", "Window overlap " + fixed$(overlapPct, 1) + "% (ripple " + fixed$(colaRipplePct, 3) + "%)"
    Text bottom: "yes", "Frames"
    Font size: 6
    Colour: colAcc$
    Text: colaSpan * 0.02, "left", 1.25, "half", "green = accumulated envelope (divided out)"

    # === PANEL: PITCH VERIFICATION ==================================
    Select outer viewport: 4, 8, 3.65, 5.35
    Select inner viewport: 4.35, 7.7, 3.75, 5.30

    pitchDrawable = 0
    if pitchOk = 1
        if medIn <> undefined and medOut <> undefined
            pitchDrawable = 1
        endif
    endif

    if pitchDrawable = 1
        pLo = medIn / 4
        pHi = medIn * 4
        if pLo < pitchFloor
            pLo = pitchFloor
        endif
        if pHi > pitchCeil
            pHi = pitchCeil
        endif
        yLo = log2(pLo)
        yHi = log2(pHi)

        Axes: 0, duration_s, yLo, yHi
        Paint rectangle: colGrey$, 0, duration_s, yLo, yHi

        Colour: colFaint$
        octLine = ceiling(yLo)
        while octLine <= yHi
            Draw line: 0, octLine, duration_s, octLine
            octLine = octLine + 1
        endwhile

        selectObject: pitchInId
        nPFin = Get number of frames
        Colour: colIn$
        Line width: 1.5
        prevT = 0
        prevF = undefined
        for i to nPFin
            selectObject: pitchInId
            fv = Get value in frame: i, "Hertz"
            tv = Get time from frame number: i
            tv = tv - xmin1
            if fv <> undefined and fv >= pLo and fv <= pHi
                if prevF <> undefined
                    Draw line: prevT, log2(prevF), tv, log2(fv)
                endif
                prevT = tv
                prevF = fv
            else
                prevF = undefined
            endif
        endfor

        selectObject: pitchOutId
        nPFout = Get number of frames
        Colour: colOut$
        prevT = 0
        prevF = undefined
        for i to nPFout
            selectObject: pitchOutId
            fv = Get value in frame: i, "Hertz"
            tv = Get time from frame number: i
            tv = tv - xmin1
            if fv <> undefined and fv >= pLo and fv <= pHi
                if prevF <> undefined
                    Draw line: prevT, log2(prevF), tv, log2(fv)
                endif
                prevT = tv
                prevF = fv
            else
                prevF = undefined
            endif
        endfor
        Line width: 1

        Colour: "Black"
        Draw inner box
        Marks bottom every: 1, duration_s / 4, "yes", "yes", "no"
        Font size: 6
        octLine = ceiling(yLo)
        while octLine <= yHi
            One mark left: octLine, "yes", "yes", "no", fixed$(2 ^ octLine, 0)
            octLine = octLine + 1
        endwhile
        Font size: 7
        Text left: "yes", "F0 (Hz, log2)"
        if measuredSt <> undefined
            Text top: "no", "Pitch: median shift " + fixed$(measuredSt, 2) + " st (asked " + fixed$(semitones, 2) + ")"
        else
            Text top: "no", "Pitch track"
        endif
        Text bottom: "yes", "Time (s)"
        Font size: 6
        Colour: colIn$
        Text: duration_s * 0.02, "left", yHi - (yHi - yLo) * 0.06, "half", "input"
        Colour: colOut$
        Text: duration_s * 0.02, "left", yHi - (yHi - yLo) * 0.14, "half", "output"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: colGrey$, 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Colour: colLabel$
        Text: 0.5, "centre", 0.55, "half", "Pitch verification unavailable"
        Text: 0.5, "centre", 0.42, "half", "(no voiced frames, or file too short)"
        Colour: "Black"
        Text top: "no", "Pitch verification"
    endif

    # === SUMMARY STRIP ==============================================
    Select outer viewport: 0, 8, 5.45, 6.25
    Select inner viewport: 0.6, 7.7, 5.50, 6.20
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if measuredSt <> undefined
        measured$ = "  measured " + fixed$(measuredSt, 2) + " st"
    else
        measured$ = "  measured n/a"
    endif

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.80, "half",
        ... "##Shift##  " + fixed$(semitones, 2) + " st"
        ... + "  ratio " + fixed$(ratio, 6)
        ... + "  gather lanes " + string$(nLanes)
        ... + "  surviving source band 0-" + fixed$(survivingHz, 0) + " Hz"
    Text: 0.02, "left", 0.50, "half",
        ... "##FFT##  " + string$(nGrain) + " pt = " + fixed$(actualFrame_s * 1000, 1) + " ms"
        ... + "  " + string$(nBins) + " bins @ " + fixed$(binWidth, 2) + " Hz"
        ... + "  hop " + string$(hop) + " (" + fixed$(overlapPct, 1) + "%)"
        ... + "  " + string$(nFrames) + " frames x " + string$(nCh) + " ch"
    Text: 0.02, "left", 0.20, "half",
        ... "##Output##  " + fixed$(duration_s, 2) + " s"
        ... + "  " + string$(nCh) + " ch"
        ... + "  peak " + fixed$(peakIn, 4) + " -> " + fixed$(peakOut, 4)
        ... + "  COLA ripple " + fixed$(colaRipplePct, 3) + "%"
        ... + measured$
        ... + "  preset=" + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete!"
endif

####################################################################
# CLEANUP
####################################################################

removeObject: wgtId, monoInId, monoOutId
if pitchInId <> 0
    removeObject: pitchInId
endif
if pitchOutId <> 0
    removeObject: pitchOutId
endif

selectObject: output_sound

####################################################################
# INFO
####################################################################

if show_info
    appendInfoLine: ""
    appendInfoLine: "=== Complete ==="
    appendInfoLine: "Output: ", output_name$
    appendInfoLine: "Duration: ", fixed$(duration_s, 3), " s   start ", fixed$(xmin1, 3), " s"
    appendInfoLine: "Channels: ", nCh
    appendInfoLine: "Peak: ", fixed$(peakIn, 4), " -> ", fixed$(peakOut, 4), " (no normalization applied)"
    appendInfoLine: ""
    appendInfoLine: "Algorithm:"
    appendInfoLine: "  Mapping: k -> round(k x ", fixed$(ratio, 6), "), magnitudes summed at collisions"
    appendInfoLine: "  Phase: instantaneous bin frequency x ratio, integrated per target bin"
    appendInfoLine: "  Discarded: source content above ", fixed$(survivingHz, 0), " Hz (past Nyquist after shift)"
    appendInfoLine: "  Gain: divided by accumulated w^2 (ripple ", fixed$(colaRipplePct, 4), "%)"
    if measuredSt <> undefined
        appendInfoLine: ""
        appendInfoLine: "Verification:"
        appendInfoLine: "  Median F0 ", fixed$(medIn, 2), " Hz -> ", fixed$(medOut, 2), " Hz"
        appendInfoLine: "  Measured shift ", fixed$(measuredSt, 3), " st   (requested ", fixed$(semitones, 3), " st)"
        appendInfoLine: "  Medians run over all voiced frames, so this tracks the requested"
        appendInfoLine: "  shift closely only when the source F0 is reasonably stable."
    endif
    if warnLines$ <> ""
        appendInfoLine: ""
        appendInfoLine: "Notes:"
        appendInfo: warnLines$
    endif
endif

if play_result
    Play
endif
