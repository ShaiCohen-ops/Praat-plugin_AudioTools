# ============================================================
# Praat AudioTools - Spectral_Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   STFT spectral morphing between two Sounds. The shorter source is
#   mapped proportionally onto the longer output timeline frame by frame.
#   Reconstruction uses periodic sqrt-Hann analysis/synthesis windows,
#   endpoint padding, overlap-weight normalization, and no automatic
#   peak normalization.
#
#   Morph modes:
#   - Log magnitude: geometric magnitude interpolation; phase follows A
#     where A has defined phase, with B-phase fallback for near-zero A bins.
#   - Full complex: linear interpolation of real and imaginary FFT values.
#
#   Morph_max_freq_Hz is an actual DSP limit: bins above it remain from A.
#   In Full-complex mode, m=0 is A and m=1 is B below the morph limit.
#   In Log-magnitude mode, m=1 has B magnitude but A reference phase below
#   the morph limit. Exact endpoint identity assumes equal source durations.
#
#   Channel handling:
#   - Equal channel counts: channels are morphed pairwise.
#   - Mono + multichannel: the mono source is reused for every output channel.
#   - Other channel-count mismatches are rejected explicitly.
#
# Changelog v3.1:
#   - Fixed endpoint OLA distortion and truncated tail with padded,
#     weight-normalized reconstruction.
#   - Removed input/output peak normalization and forced edge fades.
#   - Morph_max_freq_Hz now affects DSP; higher bins preserve Sound A.
#   - Correct geometric log-magnitude interpolation (no x30 ratio clamp).
#   - Preserves/expands compatible multichannel layouts instead of silent mono.
#   - Internal time domain normalized to 0; output start time follows Sound A.
#   - Reduced-rate processing is resampled back to Sound A's sample rate.
#   - Added attenuation-only Safety_peak.
#   - Visualization redesigned to AudioTools house style.
# Category: Time & Granular
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects."
        ... + newline$ + "Sound 1 = A (source), Sound 2 = B (target)."
endif

soundA = selected("Sound", 1)
soundB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

form Spectral Morph v3.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Tonal Sustained (instruments, pads)
        option Percussive (drums, impacts)
        option Voice Morph (speech, vocals)
        option Texture Blend (ambience, noise)
        option Fast Preview (low quality, quick)
    comment === Morph Region ===
    real Start_morph_s 0
    real End_morph_s 0
    optionmenu Curve_type: 2
        option Linear
        option Cosine (smooth S-curve)
    comment === Analysis / Morph Band ===
    positive Window_ms 60
    positive Morph_max_freq_Hz 8000
    optionmenu Speed_mode: 2
        option Full (native sample rate)
        option 22050 Hz processing
        option 11025 Hz processing
    comment === Morph Type ===
    optionmenu Morph_mode: 1
        option Log magnitude (A-reference phase)
        option Full complex (blend phase too)
    comment === Output ===
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    window_ms = 60
    morph_max_freq_Hz = 8000
    speed_mode = 2
    morph_mode = 1
    curve_type = 2
    presetName$ = "TonalSustained"
elsif preset = 3
    window_ms = 30
    morph_max_freq_Hz = 10000
    speed_mode = 2
    morph_mode = 1
    curve_type = 1
    presetName$ = "Percussive"
elsif preset = 4
    window_ms = 50
    morph_max_freq_Hz = 6000
    speed_mode = 2
    morph_mode = 1
    curve_type = 2
    presetName$ = "VoiceMorph"
elsif preset = 5
    window_ms = 80
    morph_max_freq_Hz = 12000
    speed_mode = 1
    morph_mode = 2
    curve_type = 2
    presetName$ = "TextureBlend"
elsif preset = 6
    window_ms = 120
    morph_max_freq_Hz = 5000
    speed_mode = 3
    morph_mode = 1
    curve_type = 1
    presetName$ = "FastPreview"
else
    presetName$ = "Custom"
endif

# ============================================================
# SOURCE METADATA + VALIDATION
# ============================================================
selectObject: soundA
srA = Get sampling frequency
durA = Get total duration
chA = Get number of channels
xminA = Get start time

selectObject: soundB
srB = Get sampling frequency
durB = Get total duration
chB = Get number of channels
xminB = Get start time

if durA <= 0 or durB <= 0
    exitScript: "Both Sounds must contain audio."
endif

if chA = chB
    outCh = chA
    channelMode$ = "paired " + string$(outCh) + " ch"
elsif chA = 1
    outCh = chB
    channelMode$ = "A mono duplicated to " + string$(outCh) + " ch"
elsif chB = 1
    outCh = chA
    channelMode$ = "B mono duplicated to " + string$(outCh) + " ch"
else
    exitScript: "Channel counts must match, or one source must be mono."
        ... + newline$ + "A has " + string$(chA) + " channels; B has " + string$(chB) + "."
endif

if window_ms < 2
    window_ms = 2
endif
if window_ms > 1000
    window_ms = 1000
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

# Processing rate. Final output is restored to Sound A's rate.
if speed_mode = 2
    processSR = 22050
elsif speed_mode = 3
    processSR = 11025
else
    processSR = max(srA, srB)
endif

nyquist = processSR / 2
if morph_max_freq_Hz > nyquist
    morph_max_freq_Hz = nyquist
endif
if morph_max_freq_Hz < 20
    morph_max_freq_Hz = 20
endif

# Exact even window length gives an exact 50% periodic-Hann geometry.
nWin = round(window_ms / 1000 * processSR)
if nWin < 64
    nWin = 64
endif
if (nWin mod 2) = 1
    nWin = nWin + 1
endif
hopN = nWin / 2
actualWindow_s = nWin / processSR
hop_s = hopN / processSR
binWidth = processSR / nWin

if morph_mode = 1
    modeLabel$ = "Log magnitude (A-reference phase)"
else
    modeLabel$ = "Full complex"
endif
if curve_type = 2
    curveLabel$ = "Cosine"
else
    curveLabel$ = "Linear"
endif

# ============================================================
# PREPARE SOURCES
# ============================================================
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  SPECTRAL MORPH v3.1"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "A: ", nameA$, " | ", fixed$(durA, 3), " s | ", chA, " ch | ", fixed$(srA, 0), " Hz | start ", fixed$(xminA, 3)
appendInfoLine: "B: ", nameB$, " | ", fixed$(durB, 3), " s | ", chB, " ch | ", fixed$(srB, 0), " Hz | start ", fixed$(xminB, 3)
appendInfoLine: "Channels: ", channelMode$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeLabel$, " | Curve: ", curveLabel$
appendInfoLine: "Process SR: ", processSR, " Hz | Output SR: ", fixed$(srA, 0), " Hz"
appendInfoLine: "Window: ", nWin, " samples = ", fixed$(actualWindow_s * 1000, 2), " ms | Hop: ", fixed$(hop_s * 1000, 2), " ms"
appendInfoLine: "Morph band: 0 - ", fixed$(morph_max_freq_Hz, 1), " Hz; higher bins preserve A"
appendInfoLine: ""

appendInfoLine: "[1/4] Preparing sources..."

selectObject: soundA
workA = Copy: "sm_workA"
selectObject: workA
Shift times to: "start time", 0
if srA <> processSR
    tmp = Resample: processSR, 50
    removeObject: workA
    workA = tmp
    selectObject: workA
    Rename: "sm_workA"
endif

selectObject: soundB
workB = Copy: "sm_workB"
selectObject: workB
Shift times to: "start time", 0
if srB <> processSR
    tmp = Resample: processSR, 50
    removeObject: workB
    workB = tmp
    selectObject: workB
    Rename: "sm_workB"
endif

selectObject: workA
durA_final = Get total duration
nA = Get number of samples
selectObject: workB
durB_final = Get total duration
nB = Get number of samples

commonDuration = max(durA_final, durB_final)
timeRatioA = durA_final / commonDuration
timeRatioB = durB_final / commonDuration

# Morph region on the output-relative timeline.
if end_morph_s <= start_morph_s or end_morph_s <= 0
    start_morph_s = max(0, start_morph_s)
    end_morph_s = commonDuration
endif
if start_morph_s < 0
    start_morph_s = 0
endif
if start_morph_s > commonDuration
    start_morph_s = commonDuration
endif
if end_morph_s > commonDuration
    end_morph_s = commonDuration
endif
if end_morph_s < start_morph_s
    end_morph_s = start_morph_s
endif
morphRange = end_morph_s - start_morph_s
if morphRange < 1 / processSR
    morphRange = 1 / processSR
endif

appendInfoLine: "  Working durations: A ", fixed$(durA_final, 4), " s | B ", fixed$(durB_final, 4), " s"
appendInfoLine: "  Output timeline: ", fixed$(commonDuration, 4), " s"
appendInfoLine: "  Morph region: ", fixed$(start_morph_s, 3), " - ", fixed$(end_morph_s, 3), " s"

# Output and weight buffers.
outputBuffer = Create Sound from formula: "sm_output", outCh, 0, commonDuration, processSR, "0"
weightBuffer = Create Sound from formula: "sm_weight", 1, 0, commonDuration, processSR, "0"
selectObject: outputBuffer
nOut = Get number of samples

# Frames are centered at 0, hop, 2*hop, ... plus an exact final center.
gridFrames = floor(commonDuration / hop_s) + 1
lastGridCenter = (gridFrames - 1) * hop_s
extraEndFrame = 0
if commonDuration - lastGridCenter > 0.5 / processSR
    extraEndFrame = 1
endif
totalFrames = gridFrames + extraEndFrame

# Build overlap-weight buffer once. Analysis and synthesis windows are both
# sqrt-Hann, so the accumulated effective weight is Hann = sin^2(...).
for f from 1 to totalFrames
    if f <= gridFrames
        centerOut = (f - 1) * hop_s
    else
        centerOut = commonDuration
    endif
    frameStart = centerOut - actualWindow_s / 2
    frameEnd = frameStart + actualWindow_s
    addStart = max(0, frameStart)
    addEnd = min(commonDuration, frameEnd)
    if addEnd > addStart
        selectObject: weightBuffer
        Formula (part): addStart, addEnd, 1, 1, "self + sin(pi * (x - frameStart) / actualWindow_s) ^ 2"
    endif
endfor

selectObject: weightBuffer
wMax = Get maximum: 0, 0, "None"
wMin = Get minimum: 0, 0, "None"
wEps = max(1e-12, wMax * 1e-10)

appendInfoLine: "  Frames: ", totalFrames, " | OLA weight min/max ", fixed$(wMin, 6), "/", fixed$(wMax, 6)
appendInfoLine: ""
appendInfoLine: "[2/4] STFT morphing..."

padN = nWin
padDur = padN / processSR
progressStep = floor(totalFrames / 8)
if progressStep < 1
    progressStep = 1
endif

# ============================================================
# PER-CHANNEL STFT MORPH
# ============================================================
for ch from 1 to outCh
    if chA = 1
        srcChA = 1
    else
        srcChA = ch
    endif
    if chB = 1
        srcChB = 1
    else
        srcChB = ch
    endif

    selectObject: workA
    chanA = Extract one channel: srcChA
    Rename: "sm_chanA"
    selectObject: workB
    chanB = Extract one channel: srcChB
    Rename: "sm_chanB"

    # Fixed zero padding makes every extracted STFT frame exactly nWin samples,
    # including the beginning/end and sources shorter than the analysis window.
    padA = Create Sound from formula: "sm_padA", 1, 0, (nA + 2 * padN) / processSR, processSR,
        ... "if col > padN and col <= padN + nA then object[chanA, 1, col - padN] else 0 fi"
    padB = Create Sound from formula: "sm_padB", 1, 0, (nB + 2 * padN) / processSR, processSR,
        ... "if col > padN and col <= padN + nB then object[chanB, 1, col - padN] else 0 fi"

    for f from 1 to totalFrames
        if f <= gridFrames
            centerOut = (f - 1) * hop_s
        else
            centerOut = commonDuration
        endif

        # Morph factor uses the clamped output-relative frame center.
        morphTime = min(commonDuration, max(0, centerOut))
        u = (morphTime - start_morph_s) / morphRange
        if u < 0
            u = 0
        endif
        if u > 1
            u = 1
        endif
        if curve_type = 2
            m = 0.5 - 0.5 * cos(pi * u)
        else
            m = u
        endif

        # Proportional frame-time mapping into each source.
        centerA = morphTime * timeRatioA
        centerB = morphTime * timeRatioB
        frameAstart = padDur + centerA - actualWindow_s / 2
        frameBstart = padDur + centerB - actualWindow_s / 2

        selectObject: padA
        frameA = Extract part: frameAstart, frameAstart + actualWindow_s, "rectangular", 1, "no"
        Rename: "sm_frameA"
        Formula: "self * sin(pi * (col - 0.5) / nWin)"

        selectObject: padB
        frameB = Extract part: frameBstart, frameBstart + actualWindow_s, "rectangular", 1, "no"
        Rename: "sm_frameB"
        Formula: "self * sin(pi * (col - 0.5) / nWin)"

        selectObject: frameA
        specA = To Spectrum: "no"
        selectObject: frameB
        specB = To Spectrum: "no"

        selectObject: specA
        outSpec = Copy: "sm_morphspec"
        idA = specA
        idB = specB

        selectObject: outSpec
        if morph_mode = 1
            # Geometric magnitude interpolation. At m=0 return A exactly.
            # Above the morph-frequency limit, preserve A exactly.
            Formula: "if (col - 1) * binWidth > morph_max_freq_Hz or m <= 0 then object[idA,row,col] else if sqrt(object[idA,1,col]^2+object[idA,2,col]^2) > max(1e-12, 0.001*sqrt(object[idB,1,col]^2+object[idB,2,col]^2)) then exp((1-m)*ln(max(sqrt(object[idA,1,col]^2+object[idA,2,col]^2),1e-12))+m*ln(max(sqrt(object[idB,1,col]^2+object[idB,2,col]^2),1e-12))) * object[idA,row,col] / sqrt(object[idA,1,col]^2+object[idA,2,col]^2) else if sqrt(object[idB,1,col]^2+object[idB,2,col]^2) > 1e-12 then exp((1-m)*ln(max(sqrt(object[idA,1,col]^2+object[idA,2,col]^2),1e-12))+m*ln(max(sqrt(object[idB,1,col]^2+object[idB,2,col]^2),1e-12))) * object[idB,row,col] / sqrt(object[idB,1,col]^2+object[idB,2,col]^2) else 0 fi fi fi"
        else
            Formula: "if (col - 1) * binWidth <= morph_max_freq_Hz then (1-m)*object[idA,row,col] + m*object[idB,row,col] else object[idA,row,col] fi"
        endif

        selectObject: outSpec
        frameOut = To Sound
        Override sampling frequency: processSR
        Formula: "self * sin(pi * (col - 0.5) / nWin)"
        Rename: "sm_morphfr"

        # Place the frame on its output timeline, including negative edge frames.
        frameStart = centerOut - actualWindow_s / 2
        selectObject: frameOut
        Shift times to: "start time", frameStart
        frameEnd = frameStart + actualWindow_s
        addStart = max(0, frameStart)
        addEnd = min(commonDuration, frameEnd)
        if addEnd > addStart
            selectObject: outputBuffer
            Formula (part): addStart, addEnd, ch, ch, "self + Sound_sm_morphfr(x)"
        endif

        removeObject: frameA, frameB, specA, specB, outSpec, frameOut

        if ch = 1 and (f mod progressStep) = 0
            appendInfoLine: "  ", round(100 * f / totalFrames), "%"
        endif
    endfor

    removeObject: chanA, chanB, padA, padB
    appendInfoLine: "  channel ", ch, "/", outCh, " done"
endfor

# Exact overlap normalization.
selectObject: outputBuffer
Formula: "if object[weightBuffer,1,col] > wEps then self / object[weightBuffer,1,col] else 0 fi"

# Restore Sound A's sample rate after preview-rate processing.
if processSR <> srA
    finalOutput = Resample: srA, 50
    removeObject: outputBuffer
else
    finalOutput = outputBuffer
endif

selectObject: finalOutput
Shift times to: "start time", xminA
Rename: nameA$ + "_SpectralMorph_" + nameB$

# Attenuation-only safety stage. No normalization/boosting.
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if safety_peak > 0 and peakBeforeSafety > safety_peak
    safetyGain = safety_peak / peakBeforeSafety
    Formula: "self * safetyGain"
    appendInfoLine: "  Safety attenuation: peak ", fixed$(peakBeforeSafety, 4), " -> ", fixed$(safety_peak, 4)
endif

peakFinal = Get absolute extremum: 0, 0, "None"
outputDuration = Get total duration
finalSR = Get sampling frequency

appendInfoLine: ""
appendInfoLine: "[3/4] Finalized."
appendInfoLine: "  Output: ", selected$("Sound")
appendInfoLine: "  Duration: ", fixed$(outputDuration, 4), " s | ", outCh, " ch | ", fixed$(finalSR, 0), " Hz | start ", fixed$(xminA, 3)
appendInfoLine: "  Peak: ", fixed$(peakFinal, 4), " (no normalization)"

# ============================================================
# VISUALIZATION - AUDIOTOOLS HOUSE STYLE
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[4/4] Visualization..."

    selectObject: workA
    if chA > 1
        vizA = Convert to mono
    else
        vizA = Copy: "sm_vizA"
    endif
    selectObject: workB
    if chB > 1
        vizB = Convert to mono
    else
        vizB = Copy: "sm_vizB"
    endif
    selectObject: finalOutput
    if outCh > 1
        vizOut = Convert to mono
    else
        vizOut = Copy: "sm_vizOut"
    endif
    selectObject: vizOut
    Shift times to: "start time", 0

    displayFreq = min(morph_max_freq_Hz, finalSR / 2)
    if displayFreq < 1000
        displayFreq = min(finalSR / 2, 1000)
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Title
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Spectral Morph##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.20, "half", nameA$ + " -> " + nameB$ + " | " + presetName$ + " | " + modeLabel$

    # A waveform
    Select outer viewport: 0, 8, 0.72, 1.35
    Select inner viewport: 0.55, 7.75, 0.78, 1.30
    selectObject: vizA
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "A"

    # B waveform
    Select outer viewport: 0, 8, 1.38, 2.01
    Select inner viewport: 0.55, 7.75, 1.44, 1.96
    selectObject: vizB
    Colour: "{0.48, 0.42, 0.62}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "B"

    # Output waveform
    Select outer viewport: 0, 8, 2.04, 2.67
    Select inner viewport: 0.55, 7.75, 2.10, 2.62
    selectObject: vizOut
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out"

    # Paired input spectrograms
    Select outer viewport: 0, 4, 2.74, 4.15
    Select inner viewport: 0.55, 3.82, 2.84, 4.08
    selectObject: vizA
    To Spectrogram: 0.01, displayFreq, 0.003, 20, "Gaussian"
    sgA = selected("Spectrogram")
    Paint: 0, 0, 0, displayFreq, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "A spectrum"
    removeObject: sgA

    Select outer viewport: 4, 8, 2.74, 4.15
    Select inner viewport: 4.22, 7.75, 2.84, 4.08
    selectObject: vizB
    To Spectrogram: 0.01, displayFreq, 0.003, 20, "Gaussian"
    sgB = selected("Spectrogram")
    Paint: 0, 0, 0, displayFreq, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "B spectrum"
    removeObject: sgB

    # Output spectrogram
    Select outer viewport: 0, 8, 4.22, 5.55
    Select inner viewport: 0.55, 7.75, 4.32, 5.48
    selectObject: vizOut
    To Spectrogram: 0.01, displayFreq, 0.003, 20, "Gaussian"
    sgO = selected("Spectrogram")
    Paint: 0, 0, 0, displayFreq, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Output spectrogram"
    removeObject: sgO

    # Morph curve
    Select outer viewport: 0, 8, 5.62, 6.70
    Select inner viewport: 0.55, 7.75, 5.72, 6.63
    Axes: 0, commonDuration, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, commonDuration, 0, 1
    Colour: "{0.35, 0.42, 0.68}"
    Line width: 1.5
    prevT = 0
    prevU = (0 - start_morph_s) / morphRange
    prevU = max(0, min(1, prevU))
    if curve_type = 2
        prevM = 0.5 - 0.5 * cos(pi * prevU)
    else
        prevM = prevU
    endif
    for q from 1 to 120
        curT = commonDuration * q / 120
        curU = (curT - start_morph_s) / morphRange
        curU = max(0, min(1, curU))
        if curve_type = 2
            curM = 0.5 - 0.5 * cos(pi * curU)
        else
            curM = curU
        endif
        Draw line: prevT, prevM, curT, curM
        prevT = curT
        prevM = curM
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "B mix"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 6.80, 7.55
    Select inner viewport: 0.55, 7.75, 6.86, 7.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.34}"
    Text: 0.02, "left", 0.52, "half", modeLabel$ + " | morph <= " + fixed$(morph_max_freq_Hz, 0) + " Hz | " + fixed$(actualWindow_s*1000, 1) + " ms | " + string$(totalFrames) + " frames"
    Text: 0.02, "left", 0.24, "half", channelMode$ + " | process " + string$(processSR) + " Hz -> output " + fixed$(finalSR, 0) + " Hz | peak " + fixed$(peakFinal, 4)

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizA, vizB, vizOut
    appendInfoLine: "  Visualization complete."
endif

# ============================================================
# CLEANUP + OUTPUT
# ============================================================
removeObject: workA, workB, weightBuffer
selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""

if play_output
    Play
endif
