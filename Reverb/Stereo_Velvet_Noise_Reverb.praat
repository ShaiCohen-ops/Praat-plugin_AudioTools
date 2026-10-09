# ============================================================
# Praat AudioTools - Stereo_Velvet_Noise_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Velvet Noise Reverb — an offline reverb that builds a stereo
#   impulse response (IR) from velvet noise and applies it with Praat's
#   Convolve. Pure Praat.
#
#   1. Velvet noise (strict form). Grid period Td = fs / density. In grid
#      cell m one pulse sits at round(m Td + r1 (Td - 1)) with sign +-1
#      from a second draw. The script loops over pulses, not samples.
#   2. Decay: each pulse is weighted by exp(-6.9078 t / T); the envelope
#      is -60 dB at t = T.
#   3. Two bands from the SAME pulse set: one copy decays with
#      T = RT60 x low multiplier, one with RT60 x high multiplier.
#      low  = lowpass(copy A)              (Hann band 0 .. crossover)
#      high = copy B - lowpass(copy B)     (exact complement)
#      IR = low + high. With equal multipliers this is exactly the
#      unsplit IR, because lowpass(P) + P - lowpass(P) = P.
#   4. Stereo: L and R draw their own positions and signs. In each grid
#      cell the pulse is shared with probability 1 - width, so width 0 %
#      gives identical IRs and 100 % fully independent ones.
#      Mono input: convolved with IR_L and IR_R (stereo output).
#      Stereo input: L with IR_L, R with IR_R.
#   5. The IR is scaled to unit energy per channel (mean over L and R).
#      This keeps the IR's energy, and so the wet level for broadband
#      input, steady across density and RT60; the perceived reverb level
#      can still change with the source spectrum, the band multipliers or
#      the freeze hold. 1 ms raised-cosine fade-in on the IR; pre-delay =
#      leading zeros in the IR (enforced after the band split, which is a
#      zero-phase filter and rings slightly before the first pulse);
#      equal-power dry/wet mix; optional output peak normalisation.
#      Dry/wet 0 % is a true bypass: a stereo copy of the source, no tail,
#      no level change.
#   6. Freeze approximation (optional): the decay envelope is replaced by
#      a flat hold of user-set length followed by the normal two-band
#      exponential fade-out. This is a STATIC approximation of a frozen
#      tail (one long IR), not a feedback freeze.
#
# Changelog v1.1:
#   - Dry/wet 0 % is a bypass: stereo copy of the source, no reverb tail,
#     no normalisation or peak protection (v1.0 still convolved and
#     returned source + IR length, and attenuated a full-scale peak).
#   - Pre-delay exact: IR samples before the end of the pre-delay are set
#     to zero after the band split (the zero-phase lowpass leaked about
#     -80 dB into the pre-delay when the band multipliers differed).
#   - Target peak limited to -60 .. -0.1 dBFS; the report gives the peak
#     actually reached (v1.0 capped 0 dBFS silently at 0.999).
#   - Report: pulse density actually realised; memory estimate; refusal
#     above 4 GB instead of a late out-of-memory failure.
#   - Documentation: unit IR energy keeps broadband wet level steady, not
#     the perceived level in every case.
#   - Visualisation (house style): IR waveform, band decay envelopes
#     measured against the design lines, L/R correlation of the IR over
#     time, output vs dry, summary.
#
# Changelog v1.0:
#   - First release: strict velvet-noise stereo IR (pulse loop),
#     complementary two-band decay, shared-pulse stereo width, unit-energy
#     IR, pre-delay, equal-power dry/wet, freeze approximation, presets,
#     Convolve ("sum", "zero").
#
# Requires: Praat 6.3+. Nothing else.
# ============================================================

version$ = "1.1"

# ---- INPUT: exactly one Sound (it need not be the first object) ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound (mono or stereo)."
endif
srcObj = selected ("Sound")
srcName$ = selected$ ("Sound")

# ============================================================
# FORM (short; reverb parameters in the dialog that follows)
# ============================================================
form: "Stereo Velvet Noise Reverb v1.1"
    optionmenu: "Preset", 1
        option: "Small Bright Room"
        option: "Long Dark Hall"
        option: "Glass Cloud"
        option: "Dense Wash"
        option: "Custom"
    integer: "Random seed (0 = random)", "0"
    boolean: "Freeze approximation (static, not feedback)", 0
    positive: "Freeze hold (s)", "3.0"
    boolean: "Normalize output peak", 1
    real: "Target peak (dBFS)", "-1.0"
    boolean: "Show parameters", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

# ============================================================
# PRESETS — each sets every reverb parameter
# ============================================================
rt60 = 2.0
density = 2000
crossover = 1500
lowMult = 1.0
highMult = 1.0
width = 100
preDelayMs = 10
wetDry = 35

procedure applyPreset: .p
    if .p = 1
        # Small Bright Room: short, highs decay as long as lows
        rt60 = 0.6
        density = 3000
        crossover = 2500
        lowMult = 0.9
        highMult = 1.0
        width = 60
        preDelayMs = 5
        wetDry = 25
    elsif .p = 2
        # Long Dark Hall: long lows, fast-dying highs
        rt60 = 4.5
        density = 2000
        crossover = 1200
        lowMult = 1.3
        highMult = 0.45
        width = 85
        preDelayMs = 30
        wetDry = 40
    elsif .p = 3
        # Glass Cloud: sparse (audibly grainy) pulses, long bright highs
        rt60 = 8.0
        density = 900
        crossover = 3500
        lowMult = 0.6
        highMult = 1.4
        width = 100
        preDelayMs = 60
        wetDry = 60
    elsif .p = 4
        # Dense Wash: maximum density, long and dark, mostly wet
        rt60 = 12.0
        density = 4000
        crossover = 800
        lowMult = 1.2
        highMult = 0.7
        width = 100
        preDelayMs = 15
        wetDry = 70
    endif
endproc

presetName$ = preset$
if preset < 5
    @applyPreset: preset
endif

# ============================================================
# DETAIL DIALOG (pre-filled with the preset; Custom forces it open)
# ============================================================
if show_parameters or preset = 5
    beginPause: "Velvet reverb — parameters"
        positive: "RT60 (s)", string$ (rt60)
        positive: "Density (pulses per s)", string$ (density)
        positive: "Crossover (Hz)", string$ (crossover)
        positive: "Low decay multiplier", string$ (lowMult)
        positive: "High decay multiplier", string$ (highMult)
        real: "Stereo width (%)", string$ (width)
        real: "Predelay (ms)", string$ (preDelayMs)
        real: "Dry wet (%)", string$ (wetDry)
    endPause: "Continue", 1
    rt60 = rT60
    density = density
    crossover = crossover
    lowMult = low_decay_multiplier
    highMult = high_decay_multiplier
    width = stereo_width
    preDelayMs = predelay
    wetDry = dry_wet
endif
freeze = freeze_approximation
holdS = freeze_hold

# ============================================================
# VALIDATION
# ============================================================
selectObject: srcObj
fs = Get sampling frequency
nchIn = Get number of channels
srcDur = Get total duration
srcStart = Get start time
if nchIn > 2
    exitScript: "Only mono and stereo Sounds are supported (this one has " + string$ (nchIn) + " channels)."
endif
if rt60 < 0.1 or rt60 > 60
    exitScript: "RT60 must be between 0.1 and 60 s."
endif
if density < 500 or density > 4000
    exitScript: "Density must be between 500 and 4000 pulses per second."
endif
if fs / density < 2
    exitScript: "Density too high for " + string$ (fs) + " Hz: the grid period fs / density must be at least 2 samples."
endif
if crossover < 400 or crossover > 5500
    exitScript: "Crossover must be between 400 and 5500 Hz."
endif
if crossover * 1.2 >= fs / 2
    exitScript: "Crossover " + string$ (crossover) + " Hz is too close to the Nyquist frequency (" + string$ (fs / 2) + " Hz); lower it below " + fixed$ (fs / 2 / 1.2, 0) + " Hz."
endif
if lowMult < 0.1 or lowMult > 4 or highMult < 0.1 or highMult > 4
    exitScript: "Decay multipliers must be between 0.1 and 4."
endif
if width < 0 or width > 100
    exitScript: "Stereo width must be between 0 and 100 %."
endif
if preDelayMs < 0 or preDelayMs > 500
    exitScript: "Pre-delay must be between 0 and 500 ms."
endif
if wetDry < 0 or wetDry > 100
    exitScript: "Dry wet must be between 0 and 100 %."
endif
if target_peak < -60 or target_peak > -0.1
    exitScript: "Target peak must be between -60 and -0.1 dBFS."
endif
if freeze and (holdS <= 0 or holdS > 60)
    exitScript: "Freeze hold must be between 0 and 60 s."
endif

# IR length: the slower band reaches -60 dB at RT60 x multiplier
tLow = rt60 * lowMult
tHigh = rt60 * highMult
decayLen = max (tLow, tHigh)
if freeze
    decayLen = decayLen + holdS
endif
pdN = round (preDelayMs / 1000 * fs)
irN = pdN + ceiling (decayLen * fs)
maxIrSeconds = 180
if irN / fs > maxIrSeconds or irN > 2 ^ 24
    exitScript: "The IR would be " + fixed$ (irN / fs, 1) + " s (" + string$ (irN) + " samples per channel); the practical limit is " + string$ (maxIrSeconds) + " s and 2^24 samples. Shorten RT60, the multipliers or the freeze hold."
endif

# ---- memory estimate (8 bytes per sample) ----
# peak use: three 2-channel IR-length Sounds alive at once while the
# bands are combined, plus the Hann filter's power-of-two FFT buffer, plus
# the convolution FFT (two operands and the product at the power-of-two
# length >= source + IR, two channels)
selectObject: srcObj
srcN = Get number of samples
nfftIr = 2 ^ ceiling (log2 (irN))
nfftCv = 2 ^ ceiling (log2 (srcN + irN))
memEst = 8 * (3 * 2 * irN + 2 * 2 * nfftIr + 3 * 2 * nfftCv)
if memEst > 4e9
    exitScript: "This setting needs about " + fixed$ (memEst / 1e9, 1) + " GB of working memory (IR " + fixed$ (irN / fs, 1) + " s, source " + fixed$ (srcDur, 1) + " s); the limit is 4 GB. Shorten RT60, the multipliers, the freeze hold or the source."
endif

# ============================================================
# BYPASS: dry/wet 0 % returns the source as stereo, untouched
# ============================================================
if wetDry = 0
    selectObject: srcObj
    outName$ = srcName$ + "_velvetverb"
    out = Create Sound from formula: outName$, 2, srcStart, srcStart + srcDur, fs, "object [srcObj, min (row, nchIn), col]"
    writeInfoLine: "=== Stereo Velvet Noise Reverb v", version$, " ==="
    appendInfoLine: "Dry/wet 0 %: bypass — ", outName$, " is a stereo copy of ", srcName$, " (no reverb, no level change)."
    selectObject: out
    if play_result
        Play
    endif
    exitScript ()
endif

# ============================================================
# SEED (0 = random; the seed actually used is reported)
# ============================================================
seedUsed = random_seed
if seedUsed = 0
    random_initializeSafelyAndUnpredictably ()
    seedUsed = randomInteger (1, 999999)
endif
random_initializeWithSeedUnsafelyButPredictably: seedUsed

# ============================================================
# VELVET PULSE TRAIN (one channel per side; loop over pulses only)
# ============================================================
td = fs / density
decayN = irN - pdN
nCells = floor ((decayN - 1) / td)
shareP = 1 - width / 100
pulses = Create Sound from formula: "vv_pulses", 2, 0, irN / fs, fs, "0"
nShared = 0
selectObject: pulses
for zm from 0 to nCells - 1
    # left pulse: position draw, then sign draw
    posL = round (zm * td + randomUniform (0, 1) * (td - 1))
    sgnL = if randomUniform (0, 1) < 0.5 then -1 else 1 fi
    # right pulse: shared with probability 1 - width, else its own draws
    if randomUniform (0, 1) < shareP
        posR = posL
        sgnR = sgnL
        nShared = nShared + 1
    else
        posR = round (zm * td + randomUniform (0, 1) * (td - 1))
        sgnR = if randomUniform (0, 1) < 0.5 then -1 else 1 fi
    endif
    Set value at sample number: 1, pdN + 1 + posL, sgnL
    Set value at sample number: 2, pdN + 1 + posR, sgnR
endfor
random_initializeSafelyAndUnpredictably ()
# realised density: the train is +-1, so energy per channel = pulse count
# (counts collisions too; there are none, since neighbouring cells' ranges
# are a full sample apart before rounding)
selectObject: pulses
pulseRms = Get root-mean-square: 0, 0
pulsesPlaced = pulseRms ^ 2 * irN
densityReal = pulsesPlaced / (decayN / fs)
densityDev = 100 * (densityReal / density - 1)

# ============================================================
# TWO-BAND DECAY (complementary split; equal multipliers = unsplit IR)
# ============================================================
# envelope of one band: exp(-6.9078 t / T), t from the end of the
# pre-delay; with freeze, flat for holdS and then the same decay
procedure bandEnvelope: .t
    selectObject: pulses
    .b = Copy: "vv_band"
    envT = .t
    if freeze
        Formula: "if col <= pdN then 0 else self * (if (col - 1 - pdN) / fs < holdS then 1 else exp (-6.9078 * ((col - 1 - pdN) / fs - holdS) / envT) fi) fi"
    else
        Formula: "if col <= pdN then 0 else self * exp (-6.9078 * (col - 1 - pdN) / (fs * envT)) fi"
    endif
endproc

smoothHz = 0.2 * crossover
@bandEnvelope: tLow
bandA = bandEnvelope.b
@bandEnvelope: tHigh
bandB = bandEnvelope.b
removeObject: pulses
selectObject: bandA
lowA = Filter (pass Hann band): 0, crossover, smoothHz
removeObject: bandA
selectObject: bandB
lowB = Filter (pass Hann band): 0, crossover, smoothHz
# IR = lowpass(A) + B - lowpass(B)
# (samples up to the end of the pre-delay are forced to zero: the zero-phase
# lowpass rings slightly before the first pulse)
ir = Create Sound from formula: "vv_ir", 2, 0, irN / fs, fs, "if col <= pdN then 0 else object [lowA, row, col] + object [bandB, row, col] - object [lowB, row, col] fi"
removeObject: bandB, lowA, lowB

# ---- 1 ms raised-cosine fade-in at the start of the tail ----
fadeN = max (1, round (0.001 * fs))
selectObject: ir
Formula: "if col > pdN and col - pdN <= fadeN then self * (0.5 - 0.5 * cos (pi * (col - pdN - 0.5) / fadeN)) else self fi"

# ---- unit energy per channel (mean of L and R) ----
irRms = Get root-mean-square: 0, 0
irEnergy = irRms ^ 2 * irN
if irEnergy <= 0 or irEnergy = undefined
    removeObject: ir
    exitScript: "The IR came out silent (no pulses); check the density and RT60."
endif
irScale = 1 / sqrt (irEnergy)
Formula: "self * irScale"

# ============================================================
# CONVOLUTION AND MIX
# ============================================================
selectObject: srcObj
dry = Copy: "vv_dry"
Shift times to: "start time", 0
selectObject: dry, ir
# "sum": a unit-energy IR keeps the level of white input; "zero": no
# signal assumed outside the source. Mono x stereo IR -> stereo;
# stereo x stereo -> channel-wise.
wet = Convolve: "sum", "zero"
nOut = Get number of samples
m = wetDry / 100
dryG = cos (m * pi / 2)
wetG = sin (m * pi / 2)
if m <= 0
    wetG = 0
endif
if m >= 1
    dryG = 0
endif
outName$ = srcName$ + "_velvetverb"
out = Create Sound from formula: outName$, 2, 0, nOut / fs, fs, "dryG * object [dry, min (row, nchIn), col] + wetG * object [wet, row, col]"
removeObject: wet
Shift times to: "start time", srcStart

# ---- output level ----
peakRaw = Get absolute extremum: 0, 0, "None"
levelNote$ = "none"
if peakRaw > 1e-9
    if normalize_output_peak
        Scale peak: 10 ^ (target_peak / 20)
        levelNote$ = "peak normalised to " + fixed$ (target_peak, 1) + " dBFS"
    elsif peakRaw > 0.999
        Formula: "self * 0.999 / peakRaw"
        levelNote$ = "attenuated " + fixed$ (20 * log10 (0.999 / peakRaw), 1) + " dB to avoid clipping"
    else
        levelNote$ = "not normalised (peak " + fixed$ (peakRaw, 3) + ")"
    endif
else
    levelNote$ = "output silent; not normalised"
endif
outPeak = Get absolute extremum: 0, 0, "None"
outDur = Get total duration

# ============================================================
# REPORT
# ============================================================
inTxt$ = "mono (convolved with IR L and IR R)"
if nchIn = 2
    inTxt$ = "stereo (L with IR L, R with IR R)"
endif
writeInfoLine: "=== Stereo Velvet Noise Reverb v", version$, " ==="
appendInfoLine: "Source:      ", srcName$, "  (", fixed$ (srcDur, 3), " s, ", fs, " Hz, ", inTxt$, ")"
appendInfoLine: "Preset:      ", presetName$, "   seed ", seedUsed
appendInfoLine: "Velvet:      ", fixed$ (density, 0), " pulses/s requested, ", fixed$ (densityReal, 1), " realised (", fixed$ (densityDev, 3), " %); grid ", fixed$ (td, 3), " samples; ", nCells, " pulses per channel"
appendInfoLine: "Width:       ", fixed$ (width, 0), " % (", nShared, " of ", nCells, " pulses shared between L and R)"
appendInfoLine: "Decay:       RT60 ", fixed$ (rt60, 2), " s; low band (< ", fixed$ (crossover, 0), " Hz) ", fixed$ (tLow, 2), " s, high band ", fixed$ (tHigh, 2), " s"
if freeze
    appendInfoLine: "Freeze:      static approximation — flat hold ", fixed$ (holdS, 2), " s, then the two-band decay (not a feedback freeze)"
endif
appendInfoLine: "IR:          ", fixed$ (irN / fs, 3), " s incl. ", fixed$ (preDelayMs, 0), " ms pre-delay; unit energy per channel; 1 ms fade-in"
appendInfoLine: "Mix:         wet ", fixed$ (wetDry, 0), " % (equal power: dry x", fixed$ (dryG, 3), ", wet x", fixed$ (wetG, 3), ")"
appendInfoLine: "Output:      ", outName$, "  ", fixed$ (outDur, 3), " s stereo; ", levelNote$, "; peak reached ", fixed$ (20 * log10 (max (outPeak, 1e-12)), 2), " dBFS"
appendInfoLine: "Memory:      about ", fixed$ (memEst / 1e6, 0), " MB of working memory at the peak (estimate)"

if draw_visualisation
    @drawFigure
endif
removeObject: dry, ir

# ---- selection: original objects untouched; the output is selected ----
selectObject: out
if play_result
    Play
endif

# ============================================================
# FIGURE (every curve is measured from the IR and output actually used)
# ============================================================
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor (log10 (.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure sanitize: .s$
    .s$ = replace$ (.s$, "\", "\bs", 0)
    .s$ = replace$ (.s$, "_", "\_ ", 0)
    .s$ = replace$ (.s$, "%", "\% ", 0)
    .s$ = replace$ (.s$, "#", "\# ", 0)
    .s$ = replace$ (.s$, "^", "\^ ", 0)
    .out$ = .s$
endproc

procedure drawChannels: .obj, .t0, .t1, .lim, .y0, .y1
    # channel 1 blue, channel 2 orange, drawn on a shared explicit range
    selectObject: .obj
    .nc = Get number of channels
    for zc to .nc
        selectObject: .obj
        .ch = Extract one channel: zc
        Select inner viewport: 0.6, 7.7, .y0, .y1
        if zc = 1
            Colour: "{0.20, 0.40, 0.80}"
        else
            Colour: "{0.85, 0.35, 0.15}"
        endif
        Draw: .t0, .t1, -.lim, .lim, "no", "Curve"
        removeObject: .ch
    endfor
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    .irDur = irN / fs
    .pd = pdN / fs
    .a0 = 0.95
    .a1 = 2.10
    .b0 = 2.45
    .b1 = 3.90
    .c0 = 4.25
    .c1 = 5.05
    .d0 = 5.65
    .d1 = 6.80
    .s0 = 7.40
    .s1 = 8.40
    .canvasH = 8.50

    # ---- title ----
    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Stereo Velvet Noise Reverb — " + presetName$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    @sanitize: srcName$ + "   |   RT60 " + fixed$ (rt60, 2) + " s   |   " + fixed$ (density, 0) + " pulses/s   |   width " + fixed$ (width, 0) + "%   |   seed " + string$ (seedUsed)
    Text: 0.5, "centre", 0.18, "half", sanitize.out$

    # ---- A: the IR itself ----
    selectObject: ir
    .lim = Get absolute extremum: 0, 0, "None"
    .lim = max (.lim, 1e-9) * 1.05
    Select inner viewport: 0.6, 7.7, .a0, .a1
    Axes: 0, .irDur, -.lim, .lim
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .irDur, -.lim, .lim
    @drawChannels: ir, 0, .irDur, .lim, .a0, .a1
    Select inner viewport: 0.6, 7.7, .a0, .a1
    Axes: 0, .irDur, -.lim, .lim
    Colour: "{0.45, 0.45, 0.45}"
    Dashed line
    if pdN > 0
        Draw line: .pd, -.lim, .pd, .lim
    endif
    if freeze
        Draw line: .pd + holdS, -.lim, .pd + holdS, .lim
    endif
    Solid line
    Colour: "Black"
    .t$ = "##Impulse response## — blue L, orange R; dashed: end of pre-delay"
    if freeze
        .t$ = .t$ + " and end of the freeze hold"
    endif
    Text top: "no", .t$
    Select inner viewport: 0.6, 7.7, .a0, .a1
    Axes: 0, .irDur, -.lim, .lim
    Draw inner box
    @niceStep: .irDur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @railLabel: .a0, .a1, "IR"

    # ---- B: band decay envelopes, measured vs design ----
    selectObject: ir
    # each band is measured clear of the crossover region (+-2 x smoothing),
    # where both decays overlap by design and would blur either curve
    .mLo = max (50, crossover - 2 * smoothHz)
    .mHi = min (fs / 2 * 0.95, crossover + 2 * smoothHz)
    .lowIr = Filter (pass Hann band): 0, .mLo, smoothHz / 2
    selectObject: ir
    .highIr = Filter (pass Hann band): .mHi, 0, smoothHz / 2
    .tailDur = .irDur - .pd
    .nW = max (10, min (150, floor (.tailDur / 0.02)))
    .w = .tailDur / .nW
    .hi = -300
    for zb to 2
        if zb = 1
            selectObject: .lowIr
        else
            selectObject: .highIr
        endif
        for zw to .nW
            .r = Get root-mean-square: .pd + (zw - 1) * .w, .pd + zw * .w
            bandDb_'zb'_'zw' = 20 * log10 (max (.r, 1e-12))
            .hi = max (.hi, bandDb_'zb'_'zw')
        endfor
    endfor
    .top = .hi + 5
    .bot = .hi - 85
    Select inner viewport: 0.6, 7.7, .b0, .b1
    Axes: 0, .irDur, .bot, .top
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .irDur, .bot, .top
    for zb to 2
        if zb = 1
            .col$ = "{0.20, 0.40, 0.80}"
            .tB = tLow
        else
            .col$ = "{0.85, 0.35, 0.15}"
            .tB = tHigh
        endif
        # design line: flat during the freeze hold, then -60 dB per T,
        # anchored at the band's measured level in the second window
        .ref = bandDb_'zb'_2
        .tRef = .pd + 1.5 * .w
        .tHold = .pd
        if freeze
            .tHold = .pd + holdS
        endif
        .lvl0 = .ref
        if .tRef > .tHold
            .lvl0 = .ref + 60 * (.tRef - .tHold) / .tB
        endif
        Colour: .col$
        Dotted line
        Line width: 1
        if freeze
            Draw line: .pd, .lvl0, .tHold, .lvl0
        endif
        .tEnd = min (.irDur, .tHold + .tB * (.lvl0 - .bot) / 60)
        Draw line: .tHold, .lvl0, .tEnd, .lvl0 - 60 * (.tEnd - .tHold) / .tB
        Solid line
        Line width: 1.6
        for zw from 2 to .nW
            zp = zw - 1
            Draw line: .pd + (zp - 0.5) * .w, max (.bot, bandDb_'zb'_'zp'), .pd + (zw - 0.5) * .w, max (.bot, bandDb_'zb'_'zw')
        endfor
        Line width: 1
    endfor
    removeObject: .lowIr, .highIr
    Select inner viewport: 0.6, 7.7, .b0, .b1
    Axes: 0, .irDur, .bot, .top
    Colour: "Black"
    Text top: "no", "##Band decay## — measured (solid) vs design (dotted): blue < " + fixed$ (.mLo, 0) + " Hz, T " + fixed$ (tLow, 2) + " s; orange > " + fixed$ (.mHi, 0) + " Hz, T " + fixed$ (tHigh, 2) + " s"
    Select inner viewport: 0.6, 7.7, .b0, .b1
    Axes: 0, .irDur, .bot, .top
    Draw inner box
    @niceStep: .irDur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    Marks left every: 1, 20, "yes", "yes", "no"
    @railLabel: .b0, .b1, "Level (dB)"

    # ---- C: L/R correlation of the IR over time (measured) ----
    # corr = (E(L+R) - E(L-R)) / (E(L+R) + E(L-R)) per window
    .ms = Create Sound from formula: "vv_fig_ms", 2, 0, .irDur, fs, "if row = 1 then object [ir, 1, col] + object [ir, 2, col] else object [ir, 1, col] - object [ir, 2, col] fi"
    .mid = Extract one channel: 1
    selectObject: .ms
    .side = Extract one channel: 2
    for zw to .nW
        selectObject: .mid
        .em = Get root-mean-square: .pd + (zw - 1) * .w, .pd + zw * .w
        selectObject: .side
        .es = Get root-mean-square: .pd + (zw - 1) * .w, .pd + zw * .w
        .den = .em ^ 2 + .es ^ 2
        corr_'zw' = 0
        if .den > 0
            corr_'zw' = (.em ^ 2 - .es ^ 2) / .den
        endif
    endfor
    removeObject: .ms, .mid, .side
    Select inner viewport: 0.6, 7.7, .c0, .c1
    Axes: 0, .irDur, -0.3, 1.1
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .irDur, -0.3, 1.1
    Colour: "{0.82, 0.82, 0.86}"
    Draw line: 0, 0, .irDur, 0
    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    Draw line: .pd, shareP, .irDur, shareP
    Solid line
    Colour: "{0.15, 0.60, 0.35}"
    Line width: 1.6
    for zw from 2 to .nW
        zp = zw - 1
        Draw line: .pd + (zp - 0.5) * .w, corr_'zp', .pd + (zw - 0.5) * .w, corr_'zw'
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, .c0, .c1
    Axes: 0, .irDur, -0.3, 1.1
    Colour: "Black"
    Text top: "no", "##L/R correlation of the IR## (measured) — dotted: shared-pulse fraction 1 - width = " + fixed$ (shareP, 2)
    Select inner viewport: 0.6, 7.7, .c0, .c1
    Axes: 0, .irDur, -0.3, 1.1
    Draw inner box
    @niceStep: .irDur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "IR time (s)"
    @railLabel: .c0, .c1, "Corr"

    # ---- D: output vs dry ----
    selectObject: out
    .lim2 = Get absolute extremum: 0, 0, "None"
    selectObject: dry
    .dpk = Get absolute extremum: 0, 0, "None"
    .lim2 = max (.lim2, .dpk * dryG, 1e-9) * 1.05
    Select inner viewport: 0.6, 7.7, .d0, .d1
    Axes: 0, outDur, -.lim2, .lim2
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, outDur, -.lim2, .lim2
    selectObject: dry
    .dm = Convert to mono
    Formula: "self * dryG"
    Select inner viewport: 0.6, 7.7, .d0, .d1
    Colour: "{0.72, 0.72, 0.76}"
    Draw: 0, outDur, -.lim2, .lim2, "no", "Curve"
    removeObject: .dm
    @drawChannels: out, srcStart, srcStart + outDur, .lim2, .d0, .d1
    Select inner viewport: 0.6, 7.7, .d0, .d1
    Axes: 0, outDur, -.lim2, .lim2
    Colour: "Black"
    Text top: "no", "##Output## — blue L, orange R; grey: dry part of the mix (before normalisation)"
    Select inner viewport: 0.6, 7.7, .d0, .d1
    Axes: 0, outDur, -.lim2, .lim2
    Draw inner box
    @niceStep: outDur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time from the start of the source (s)"
    @railLabel: .d0, .d1, "Output"

    # ---- summary ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.85, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    @sanitize: "Velvet noise: " + fixed$ (density, 0) + " pulses/s requested, " + fixed$ (densityReal, 1) + " realised; grid " + fixed$ (td, 2) + " samples; " + string$ (nCells) + " pulses per channel, " + string$ (nShared) + " shared"
    Text: 0.012, "left", 0.64, "half", sanitize.out$
    .fz$ = ""
    if freeze
        .fz$ = "   |   freeze: static hold " + fixed$ (holdS, 2) + " s (not feedback)"
    endif
    @sanitize: "Decay: RT60 " + fixed$ (rt60, 2) + " s; low " + fixed$ (tLow, 2) + " s, high " + fixed$ (tHigh, 2) + " s, crossover " + fixed$ (crossover, 0) + " Hz" + .fz$
    Text: 0.012, "left", 0.45, "half", sanitize.out$
    @sanitize: "IR " + fixed$ (irN / fs, 2) + " s incl. " + fixed$ (preDelayMs, 0) + " ms pre-delay, unit energy per channel   |   wet " + fixed$ (wetDry, 0) + "% equal power   |   " + inTxt$
    Text: 0.012, "left", 0.26, "half", sanitize.out$
    @sanitize: "Output " + fixed$ (outDur, 2) + " s stereo; " + levelNote$ + "; peak reached " + fixed$ (20 * log10 (max (outPeak, 1e-12)), 2) + " dBFS"
    Text: 0.012, "left", 0.08, "half", sanitize.out$
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, .canvasH
endproc
