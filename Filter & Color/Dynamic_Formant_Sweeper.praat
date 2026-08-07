# ============================================================
# Praat AudioTools - Dynamic Formant Sweeper v1.0
# Spectral-envelope LFO processor
#
# Architecture:
#   - NO LPC resynthesis
#   - NO inverse filtering
#   - NO FormantGrid filtering
#   - Formant analysis supplies a robust F1 LANDMARK only
#   - The original complex STFT spectrum is multiplied by a smooth,
#     real-valued moving gain curve, preserving phase bin by bin
#   - Hann analysis + Hann synthesis + Hann^2 weighted overlap-add
#   - Integer-sample grain/hop geometry
#
# The original F1 region is estimated robustly from its median and
# interquartile spread. The LFO controls a new spectral-envelope peak.
# This avoids time-varying LPC poles and the tremolo/warble they can
# create on sustained material.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

inputSound = selected("Sound")
originalName$ = selected$("Sound")

form Dynamic Formant Sweeper v1.0
    optionmenu Preset: 1
        option Manual
        option Gentle Vowel Morph
        option Robot Voice
        option Talking Synth
        option Underwater
        option Alien Speech
        option Fast Wobble
        option Slow Sweep
    comment === LFO Parameters ===
    real Rate_Hz 1.0
    positive Min_freq_Hz 500
    positive Max_freq_Hz 3500
    optionmenu Lfo_shape: 1
        option Sine
        option Triangle
        option Square (Chopper)
        option Sawtooth
        option Reverse Sawtooth
    comment === Spectral Envelope ===
    positive Envelope_width_Hz 360
    positive Sweep_strength_dB 14
    boolean Preserve_frame_energy 1
    comment === Analysis ===
    optionmenu Analysis_source: 2
        option Channel 1
        option Loudest channel
        option Mono sum (cancels anti-phase)
    positive Formant_time_step_ms 10
    positive Formant_window_ms 30
    positive Formant_ceiling_Hz 5500
    comment === Processing ===
    real Dry_wet_mix 1.0
    boolean Apply_high_cut 0
    positive High_cut_Hz 8000
    boolean Apply_fades 0
    positive Fade_ms 10
    comment === Output ===
    optionmenu Output_level_mode: 2
        option None (natural level)
        option Match input RMS + safety ceiling
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
if preset = 2
    rate_Hz = 0.3
    min_freq_Hz = 700
    max_freq_Hz = 1200
    envelope_width_Hz = 330
    sweep_strength_dB = 8
    lfo_shape = 1
    dry_wet_mix = 0.65
    presetName$ = "GentleVowelMorph"
elsif preset = 3
    rate_Hz = 2.0
    min_freq_Hz = 400
    max_freq_Hz = 2000
    envelope_width_Hz = 450
    sweep_strength_dB = 20
    lfo_shape = 3
    dry_wet_mix = 0.90
    presetName$ = "RobotVoice"
elsif preset = 4
    rate_Hz = 0.5
    min_freq_Hz = 600
    max_freq_Hz = 1800
    envelope_width_Hz = 390
    sweep_strength_dB = 15
    lfo_shape = 2
    dry_wet_mix = 0.80
    presetName$ = "TalkingSynth"
elsif preset = 5
    rate_Hz = 0.2
    min_freq_Hz = 300
    max_freq_Hz = 800
    envelope_width_Hz = 660
    sweep_strength_dB = 13
    lfo_shape = 1
    dry_wet_mix = 0.90
    presetName$ = "Underwater"
elsif preset = 6
    rate_Hz = 1.5
    min_freq_Hz = 800
    max_freq_Hz = 3000
    envelope_width_Hz = 360
    sweep_strength_dB = 22
    lfo_shape = 4
    dry_wet_mix = 0.85
    presetName$ = "AlienSpeech"
elsif preset = 7
    rate_Hz = 4.0
    min_freq_Hz = 500
    max_freq_Hz = 2500
    envelope_width_Hz = 390
    sweep_strength_dB = 17
    lfo_shape = 1
    dry_wet_mix = 0.75
    presetName$ = "FastWobble"
elsif preset = 8
    rate_Hz = 0.1
    min_freq_Hz = 400
    max_freq_Hz = 3500
    envelope_width_Hz = 450
    sweep_strength_dB = 20
    lfo_shape = 5
    dry_wet_mix = 1.0
    presetName$ = "SlowSweep"
else
    presetName$ = "Manual"
endif

# ------------------------------------------------------------
# Input / validation
# ------------------------------------------------------------
selectObject: inputSound
duration = Get total duration
sampleRate = Get sampling frequency
nChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2
inputPeak = Get absolute extremum: 0, 0, "None"
inputRMS = Get root-mean-square: 0, 0

timeStepSec = formant_time_step_ms / 1000
windowSec = formant_window_ms / 1000

if duration < max(0.15, windowSec * 3)
    exitScript: "Sound is too short for stable formant analysis."
endif
if min_freq_Hz >= max_freq_Hz
    exitScript: "Min_freq_Hz must be below Max_freq_Hz."
endif
if min_freq_Hz <= 0 or max_freq_Hz >= nyquist - 20
    exitScript: "The LFO frequency range must stay between 0 and Nyquist."
endif
if envelope_width_Hz <= 0
    exitScript: "Envelope_width_Hz must be greater than zero."
endif
if sweep_strength_dB <= 0 or sweep_strength_dB > 36
    exitScript: "Sweep_strength_dB must be greater than 0 and at most 36 dB."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1."
endif
if inputRMS < 0.0000001
    exitScript: "The input is silent or effectively silent."
endif

# FormantPath probes ceilings around the requested centre.
formant_ceiling_Hz = min(formant_ceiling_Hz, (nyquist - 50) / 1.22)
if formant_ceiling_Hz < 900
    exitScript: "Sample rate is too low for useful F1 analysis."
endif

highCut = high_cut_Hz
if highCut > nyquist - 100
    highCut = nyquist - 100
endif

# Full bypass before analysis/FFT/output-level processing.
if dry_wet_mix = 0
    selectObject: inputSound
    finalOutput = Copy: originalName$ + "_swept_Bypass"
    if play_result
        Play
    endif
    selectObject: finalOutput
    exitScript: ""
endif

clearinfo
writeInfoLine: "=== Dynamic Formant Sweeper v1.0 ==="
appendInfoLine: "Method: moving spectral envelope, magnitude only, original phase."
appendInfoLine: "No LPC resynthesis, inverse filtering, or FormantGrid filtering."
appendInfoLine: "Input: ", originalName$, " | ", fixed$(duration, 2), " s | ", nChannels,
    ... " ch | ", sampleRate, " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "LFO: ", fixed$(rate_Hz, 3), " Hz | target F1 ",
    ... fixed$(min_freq_Hz, 0), "-", fixed$(max_freq_Hz, 0), " Hz"
appendInfoLine: "Strength: ", fixed$(sweep_strength_dB, 1), " dB | BW control ",
    ... fixed$(envelope_width_Hz, 0), " Hz"
appendInfoLine: ""

# ------------------------------------------------------------
# Work copy at time zero
# ------------------------------------------------------------
selectObject: inputSound
workSound = Copy: "dfs_work"
Shift times to: "start time", 0

# ------------------------------------------------------------
# Analysis source
# ------------------------------------------------------------
if nChannels = 1
    selectObject: workSound
    analysisSound = Copy: "dfs_analysis"
    analysisSource$ = "single channel"
elsif analysis_source = 3
    selectObject: workSound
    analysisSound = Convert to mono
    analysisSource$ = "mono sum"
else
    pickCh = 1
    if analysis_source = 2
        bestRms = -1
        for ch from 1 to nChannels
            selectObject: workSound
            probeCh = Extract one channel: ch
            probeRms = Get root-mean-square: 0, 0
            removeObject: probeCh
            if probeRms > bestRms
                bestRms = probeRms
                pickCh = ch
            endif
        endfor
    endif
    selectObject: workSound
    analysisSound = Extract one channel: pickCh
    analysisSource$ = "channel " + string$(pickCh)
endif

selectObject: analysisSound
analysisRMS = Get root-mean-square: 0, 0
if analysisRMS = undefined or analysisRMS < 0.0000001
    removeObject: analysisSound, workSound
    if analysis_source = 3 and nChannels > 1
        exitScript: "The mono analysis sum cancelled. Use Loudest channel or Channel 1."
    else
        exitScript: "The selected analysis channel is silent."
    endif
endif
appendInfoLine: "Analysis source: ", analysisSource$

# ------------------------------------------------------------
# Robust F1 landmark only
# ------------------------------------------------------------
appendInfoLine: "[1/3] Measuring the original F1 region..."
selectObject: analysisSound
formantPath = To FormantPath (burg): timeStepSec, 5, formant_ceiling_Hz,
    ... windowSec, 35, 0.05, 4
formantObj = Extract Formant

selectObject: formantObj
f1Median = Get quantile: 1, 0, 0, "Hertz", 0.50
f1Q25 = Get quantile: 1, 0, 0, "Hertz", 0.25
f1Q75 = Get quantile: 1, 0, 0, "Hertz", 0.75

if f1Median = undefined or f1Median <= 0
    removeObject: formantPath, formantObj, analysisSound, workSound
    exitScript: "No reliable F1 landmark was found."
endif

if f1Q25 = undefined
    f1Q25 = f1Median
endif
if f1Q75 = undefined
    f1Q75 = f1Median
endif
f1Spread = max(0, f1Q75 - f1Q25)

# These are envelope widths, not LPC bandwidths.
# The source region is deliberately broad enough to cover natural F1 motion.
targetWidth = max(180, envelope_width_Hz)
sourceWidth = max(targetWidth, 180 + 1.8 * f1Spread)

appendInfoLine: "  F1 median: ", fixed$(f1Median, 1), " Hz"
appendInfoLine: "  F1 IQR: ", fixed$(f1Q25, 1), "-", fixed$(f1Q75, 1), " Hz"
appendInfoLine: "  Envelope widths: source ", fixed$(sourceWidth, 0),
    ... " Hz, target ", fixed$(targetWidth, 0), " Hz"

removeObject: formantPath, formantObj, analysisSound

# ------------------------------------------------------------
# Adaptive integer-sample WOLA geometry
# ------------------------------------------------------------
appendInfoLine: "[2/3] Building the moving spectral envelope..."

# At least 20 updates/s for ordinary motion, and ~16 updates per LFO cycle.
updateHz = max(20, min(80, 16 * abs(rate_Hz)))
if rate_Hz = 0
    updateHz = 20
endif
hopSamples = round(sampleRate / updateHz)
if hopSamples < 1
    hopSamples = 1
endif
hopSec = hopSamples / sampleRate

# Two-hop analysis window, with a 40 ms minimum for low-frequency resolution.
grainSamples = max(round(0.040 * sampleRate), 2 * hopSamples)
# Keep the grain below 100 ms so transients are not excessively smeared.
grainSamples = min(grainSamples, round(0.100 * sampleRate))
if grainSamples < 8
    grainSamples = 8
endif
grainSec = grainSamples / sampleRate

selectObject: workSound
totalSamples = Get number of samples
padHeadSamples = floor(grainSamples / 2)
coreEndSample = padHeadSamples + totalSamples
desiredEndSample = coreEndSample + padHeadSamples
numGrains = ceiling((desiredEndSample - grainSamples) / hopSamples) + 1
if numGrains < 1
    numGrains = 1
endif
lastStartSample = 1 + (numGrains - 1) * hopSamples
lastEndSample = lastStartSample + grainSamples - 1
if lastEndSample < desiredEndSample
    numGrains = numGrains + 1
    lastStartSample = 1 + (numGrains - 1) * hopSamples
    lastEndSample = lastStartSample + grainSamples - 1
endif
padTailSamples = max(0, lastEndSample - coreEndSample)
paddedSamples = padHeadSamples + totalSamples + padTailSamples
paddedDur = paddedSamples / sampleRate
padHead = padHeadSamples / sampleRate
padTail = padTailSamples / sampleRate

appendInfoLine: "  Grain ", fixed$(grainSec * 1000, 1), " ms | hop ",
    ... fixed$(hopSec * 1000, 1), " ms | updates ", fixed$(1 / hopSec, 1), "/s"
appendInfoLine: "  Grains/channel: ", numGrains

# Precompute LFO target once per grain.
freqRange = max_freq_Hz - min_freq_Hz
freqMid = min_freq_Hz + freqRange / 2
twoPi = 2 * pi
for g from 1 to numGrains
    s1 = 1 + (g - 1) * hopSamples
    grainStart = (s1 - 1) / sampleRate
    sourceTime = grainStart + grainSec / 2 - padHead
    if sourceTime < 0
        sourceTime = 0
    endif
    if sourceTime > duration
        sourceTime = duration
    endif
    if lfo_shape = 1
        targetF1[g] = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * sourceTime))
    elsif lfo_shape = 2
        targetF1[g] = freqMid + (freqRange / 2) * (2 / pi) * arcsin(sin(twoPi * rate_Hz * sourceTime))
    elsif lfo_shape = 3
        if sin(twoPi * rate_Hz * sourceTime) > 0
            targetF1[g] = max_freq_Hz
        else
            targetF1[g] = min_freq_Hz
        endif
    elsif lfo_shape = 4
        targetF1[g] = min_freq_Hz + freqRange * ((rate_Hz * sourceTime) mod 1)
    else
        targetF1[g] = max_freq_Hz - freqRange * ((rate_Hz * sourceTime) mod 1)
    endif
endfor

# Synthesis Hann and Hann^2 weight buffer.
Create Sound from formula: "dfs_ones", 1, 0, grainSec, sampleRate, "1"
ones = selected("Sound")
selectObject: ones
synthWin = Extract part: 0, grainSec, "Hanning", 1, "no"
winNs = Get number of samples
synthWin$ = string$(synthWin)
removeObject: ones

# Use the actual window length Praat returned as the synthesis length.
if winNs <> grainSamples
    grainSamples = winNs
    grainSec = grainSamples / sampleRate
endif

Create Sound from formula: "dfs_weight", 1, 0, paddedDur, sampleRate, "0"
weightBuf = selected("Sound")
weightBuf$ = string$(weightBuf)

for g from 1 to numGrains
    s1 = 1 + (g - 1) * hopSamples
    s2 = s1 + grainSamples - 1
    if s2 > paddedSamples
        s2 = paddedSamples
    endif
    grainS1[g] = s1
    if s2 >= s1
        off = s1 - 1
        selectObject: weightBuf
        Formula (part): (s1 - 0.75) / sampleRate, (s2 - 0.25) / sampleRate, 1, 1,
            ... "self + object[" + synthWin$ + ", 1, col - " + string$(off) +
            ... "] * object[" + synthWin$ + ", 1, col - " + string$(off) + "]"
    endif
endfor

trimStart = padHeadSamples + 1
trimEnd = padHeadSamples + totalSamples
energyClampLin = 10 ^ (3 / 20)
shapeClamp$ = fixed$(sweep_strength_dB, 4)

procedure sweepChannel: .inputSound
    Create Sound from formula: "dfs_head", 1, 0, padHead, sampleRate, "0"
    .head = selected("Sound")
    selectObject: .inputSound
    .mid = Copy: "dfs_mid"
    Create Sound from formula: "dfs_tail", 1, 0, padTail, sampleRate, "0"
    .tail = selected("Sound")
    selectObject: .head
    plusObject: .mid
    plusObject: .tail
    Concatenate
    .padded = selected("Sound")
    removeObject: .head, .mid, .tail

    Create Sound from formula: "dfs_acc", 1, 0, paddedDur, sampleRate, "0"
    .acc = selected("Sound")

    for g from 1 to numGrains
        .s1 = grainS1[g]
        .s2 = .s1 + grainSamples - 1
        if .s2 > paddedSamples
            .s2 = paddedSamples
        endif
        .gs = (.s1 - 1) / sampleRate
        .ge = (.s1 - 1 + grainSamples) / sampleRate
        if .ge > paddedDur
            .ge = paddedDur
        endif

        selectObject: .padded
        .grain = Extract part: .gs, .ge, "Hanning", 1, "no"
        selectObject: .grain
        .spec = To Spectrum: "yes"

        .target = targetF1[g]
        .amp = sweep_strength_dB

        # Move envelope energy from the robust original F1 region to
        # the LFO target. Broad Gaussian-like bells, never narrow poles.
        # Real and imaginary bins get the same scalar => phase preserved.
        selectObject: .spec
        if preserve_frame_energy
            .eIn = Get band energy: 0, 0
        endif
        Formula: "self * 10^(min(" + shapeClamp$ + ", max(-" + shapeClamp$ + ", " +
            ... fixed$(.amp, 4) + " * (exp(-((x-" + fixed$(.target, 3) + ")/" +
            ... fixed$(targetWidth, 3) + ")^2) - exp(-((x-" + fixed$(f1Median, 3) + ")/" +
            ... fixed$(sourceWidth, 3) + ")^2)))) / 20)"

        if preserve_frame_energy
            .eOut = Get band energy: 0, 0
            if .eIn > 0 and .eOut > 0
                .corr = sqrt(.eIn / .eOut)
                if .corr > energyClampLin
                    .corr = energyClampLin
                endif
                if .corr < 1 / energyClampLin
                    .corr = 1 / energyClampLin
                endif
                selectObject: .spec
                Formula: "self * " + fixed$(.corr, 8)
            endif
        endif

        selectObject: .spec
        To Sound
        .back = selected("Sound")
        removeObject: .grain, .spec

        if .s2 >= .s1
            .off = .s1 - 1
            selectObject: .acc
            Formula (part): (.s1 - 0.75) / sampleRate, (.s2 - 0.25) / sampleRate, 1, 1,
                ... "self + object[" + string$(.back) + ", 1, col - " + string$(.off) +
                ... "] * object[" + synthWin$ + ", 1, col - " + string$(.off) + "]"
        endif
        removeObject: .back
    endfor

    removeObject: .padded

    selectObject: .acc
    Formula: "if object[" + weightBuf$ + ", 1, col] > 0.000001 then self / object[" +
        ... weightBuf$ + ", 1, col] else 0 endif"

    selectObject: .acc
    Extract part: (trimStart - 1) / sampleRate, trimEnd / sampleRate, "rectangular", 1, "no"
    .out = selected("Sound")
    removeObject: .acc
    selectObject: .out
endproc

# ------------------------------------------------------------
# Process every channel and assemble
# ------------------------------------------------------------
appendInfoLine: "[3/3] Processing ", nChannels, " channel(s)..."
for ch from 1 to nChannels
    if nChannels = 1
        selectObject: workSound
        dryCh[ch] = Copy: "dfs_dry"
    else
        selectObject: workSound
        dryCh[ch] = Extract one channel: ch
    endif

    @sweepChannel: dryCh[ch]
    wetCh[ch] = selected("Sound")

    if apply_high_cut and highCut > 100
        selectObject: wetCh[ch]
        hc = Filter (pass Hann band): 0, highCut, 100
        removeObject: wetCh[ch]
        wetCh[ch] = hc
    endif

    if apply_fades
        fadeSec = min(fade_ms / 1000, duration / 4)
        if fadeSec > 0
            selectObject: wetCh[ch]
            Formula: "if x < " + string$(fadeSec) + " then self * x / " + string$(fadeSec) + " else self endif"
            Formula: "if x > " + string$(duration - fadeSec) + " then self * (" +
                ... string$(duration) + " - x) / " + string$(fadeSec) + " else self endif"
        endif
    endif

    if dry_wet_mix < 1
        selectObject: wetCh[ch]
        Formula: "self * " + string$(dry_wet_mix) + " + object[" + string$(dryCh[ch]) +
            ... ", 1, col] * " + string$(1 - dry_wet_mix)
    endif
endfor

if nChannels = 1
    selectObject: wetCh[1]
    finalOutput = Copy: "dfs_out"
else
    Create Sound from formula: "dfs_out", nChannels, 0, duration, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to nChannels
        selectObject: finalOutput
        Formula (part): 0, duration, ch, ch,
            ... "object[" + string$(wetCh[ch]) + ", 1, col]"
    endfor
endif

for ch from 1 to nChannels
    removeObject: dryCh[ch], wetCh[ch]
endfor
removeObject: synthWin, weightBuf

# ------------------------------------------------------------
# Output level
# ------------------------------------------------------------
selectObject: finalOutput
preLevelPeak = Get absolute extremum: 0, 0, "None"
preLevelRMS = Get root-mean-square: 0, 0
levelGain = 1
levelAction$ = "natural level"

if output_level_mode = 2
    if preLevelRMS > 0.0000001 and inputRMS > 0.0000001
        levelGain = inputRMS / preLevelRMS
        Formula: "self * " + string$(levelGain)
        levelAction$ = "matched input RMS"
        p = Get absolute extremum: 0, 0, "None"
        if p > ceiling_peak
            Scale peak: ceiling_peak
            levelAction$ = "RMS matched, then ceiling applied"
        endif
    endif
elsif output_level_mode = 3
    if preLevelPeak > ceiling_peak
        Scale peak: ceiling_peak
        levelAction$ = "ceiling applied"
    else
        levelAction$ = "ceiling not needed"
    endif
elsif output_level_mode = 4
    if preLevelPeak > 0
        Scale peak: ceiling_peak
        levelAction$ = "peak normalized"
    endif
endif

selectObject: finalOutput
outPeak = Get absolute extremum: 0, 0, "None"
outRMS = Get root-mean-square: 0, 0

# ------------------------------------------------------------
# Visualization - house style, capped to an 8-second view
# ------------------------------------------------------------
if draw_visualization
    vizDur = min(duration, 8)
    vizStart = max(0, (duration - vizDur) / 2)
    vizEnd = vizStart + vizDur
    specCeil = min(5000, nyquist)

    Erase all

    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Dynamic Formant Sweeper##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.0, "half", originalName$ + "  |  " + presetName$

    # LFO panel
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    Axes: vizStart, vizEnd, min_freq_Hz - 100, max_freq_Hz + 100
    Paint rectangle: "{0.95, 0.95, 0.95}", vizStart, vizEnd,
        ... min_freq_Hz - 100, max_freq_Hz + 100
    Colour: "{0.80, 0.50, 0.20}"
    Line width: 2
    nPoints = 240
    for i from 2 to nPoints
        t1 = vizStart + (i - 2) / (nPoints - 1) * vizDur
        t2 = vizStart + (i - 1) / (nPoints - 1) * vizDur
        if lfo_shape = 1
            y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t1))
            y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 2
            y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t1))
            y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 3
            if sin(twoPi * rate_Hz * t1) > 0
                y1 = max_freq_Hz
            else
                y1 = min_freq_Hz
            endif
            if sin(twoPi * rate_Hz * t2) > 0
                y2 = max_freq_Hz
            else
                y2 = min_freq_Hz
            endif
        elsif lfo_shape = 4
            y1 = min_freq_Hz + freqRange * ((rate_Hz * t1) mod 1)
            y2 = min_freq_Hz + freqRange * ((rate_Hz * t2) mod 1)
        else
            y1 = max_freq_Hz - freqRange * ((rate_Hz * t1) mod 1)
            y2 = max_freq_Hz - freqRange * ((rate_Hz * t2) mod 1)
        endif
        Draw line: t1, y1, t2, y2
    endfor
    Colour: "{0.30, 0.35, 0.65}"
    Draw line: vizStart, f1Median, vizEnd, f1Median
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "LFO target; dotted = measured F1 median"

    # Output spectrogram
    Select outer viewport: 0, 8, 2.0, 4.8
    Select inner viewport: 0.6, 7.6, 2.1, 4.7
    selectObject: finalOutput
    if nChannels > 1
        vizMono = Convert to mono
    else
        vizMono = Copy: "dfs_viz"
    endif
    selectObject: vizMono
    vizPart = Extract part: vizStart, vizEnd, "rectangular", 1, "no"
    selectObject: vizPart
    spec = To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: vizMono, vizPart, spec

    Select inner viewport: 0.6, 7.6, 2.1, 4.7
    Axes: vizStart, vizEnd, 0, specCeil
    Colour: "Yellow"
    Line width: 2
    for i from 2 to nPoints
        t1 = vizStart + (i - 2) / (nPoints - 1) * vizDur
        t2 = vizStart + (i - 1) / (nPoints - 1) * vizDur
        if lfo_shape = 1
            y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t1))
            y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 2
            y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t1))
            y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 3
            if sin(twoPi * rate_Hz * t1) > 0
                y1 = max_freq_Hz
            else
                y1 = min_freq_Hz
            endif
            if sin(twoPi * rate_Hz * t2) > 0
                y2 = max_freq_Hz
            else
                y2 = min_freq_Hz
            endif
        elsif lfo_shape = 4
            y1 = min_freq_Hz + freqRange * ((rate_Hz * t1) mod 1)
            y2 = min_freq_Hz + freqRange * ((rate_Hz * t2) mod 1)
        else
            y1 = max_freq_Hz - freqRange * ((rate_Hz * t1) mod 1)
            y2 = max_freq_Hz - freqRange * ((rate_Hz * t2) mod 1)
        endif
        Draw line: t1, y1, t2, y2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s) - yellow = spectral-envelope target"

    # Summary
    Select outer viewport: 0, 8, 4.9, 5.7
    Select inner viewport: 0.6, 7.6, 5.0, 5.6
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.50, "half",
        ... "F1 median " + fixed$(f1Median, 0) + " Hz"
        ... + "  |  source/target width " + fixed$(sourceWidth, 0) + "/" + fixed$(targetWidth, 0) + " Hz"
        ... + "  |  strength " + fixed$(sweep_strength_dB, 1) + " dB"
        ... + "  |  grain/hop " + fixed$(grainSec*1000, 1) + "/" + fixed$(hopSec*1000, 1) + " ms"
    Text: 0.02, "left", 0.18, "half",
        ... "Peak " + fixed$(inputPeak, 3) + " -> " + fixed$(outPeak, 3)
        ... + "  |  RMS " + fixed$(inputRMS, 4) + " -> " + fixed$(outRMS, 4)
        ... + "  |  " + levelAction$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
endif

# ------------------------------------------------------------
# Restore domain / cleanup / finish
# ------------------------------------------------------------
selectObject: finalOutput
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_swept_" + presetName$
finalName$ = selected$("Sound")

removeObject: workSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "  F1 landmark: ", fixed$(f1Median, 1), " Hz"
appendInfoLine: "  Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(outPeak, 4)
appendInfoLine: "  RMS:  ", fixed$(inputRMS, 5), " -> ", fixed$(outRMS, 5)
appendInfoLine: "  Output stage: ", levelAction$
if output_level_mode <> 4 and outPeak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and may clip in integer PCM."
endif

if play_result
    selectObject: finalOutput
    if outPeak > 1
        playCopy = Copy: "dfs_play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        Play
    endif
endif

selectObject: finalOutput
