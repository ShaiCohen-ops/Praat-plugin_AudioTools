# ============================================================
# Praat AudioTools - Wah-Wah_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Offline stereo/multichannel spectral wah. A time-varying Hann-band
#   response is applied in an STFT overlap-add engine. The center frequency
#   can follow a sine LFO or the source amplitude envelope.
#
#   Resonance is a spectral peak multiplier at the current center frequency
#   (1 = no extra peak). It is not an analog-pedal Q model.
#
#   Channel behavior:
#     - mono input -> stereo output (L/R LFO phase offset)
#     - 2+ channel input -> channel count preserved; LFO phase offsets are
#       distributed from 0 to Stereo_offset cycles across channels
#     - Envelope Follower uses the same envelope-derived center on all channels
#
# Changelog v0.4:
#   - Replaced hard segment processing with continuous sqrt-Hann STFT/OLA.
#   - Added real Envelope Follower mode; Auto-Wah now follows source level.
#   - Removed unconditional peak normalization; added attenuation-only safety.
#   - Wet=0 is an exact dry bypass (mono is duplicated to stereo by design).
#   - Preserves non-zero start times and arbitrary multichannel input.
#   - Clarified Resonance as a spectral peak multiplier, not analog Q.
#   - Renamed misleading Talk Box / Crying Baby style labels.
# ============================================================

form Wah-Wah Effect v0.4
    optionmenu Preset: 1
        option Custom
        option Classic Wah (slow)
        option Funky Wah (fast)
        option Auto-Wah (envelope follower)
        option Crying Wah
        option Talk-Box-like Sweep
        option Subtle Sweep
    comment === Modulation ===
    optionmenu Modulation_mode: 1
        option Sine LFO
        option Envelope Follower
    positive Wah_rate_(Hz) 1.5
    positive Envelope_attack_(ms) 12
    positive Envelope_release_(ms) 100
    positive Envelope_range_(dB) 30
    comment === Wah Parameters ===
    positive Min_frequency_(Hz) 300
    positive Max_frequency_(Hz) 2000
    positive Bandwidth_(Hz) 400
    positive Resonance_peak 2.0
    comment (1 = flat passband center; higher = extra spectral peak)
    comment === Spatial Modulation ===
    real Stereo_offset_(cycles) 0.10
    comment (LFO mode only; 0-0.5 cycles distributed across output channels)
    comment === Mix / Safety ===
    real Wet_dry_percent 75
    real Safety_peak 0.99
    comment (Safety_peak <= 0 disables safety attenuation; never boosts)
    comment === Output ===
    boolean Draw_response 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    modulation_mode = 1
    wah_rate = 0.8
    min_frequency = 400
    max_frequency = 1800
    bandwidth = 350
    resonance_peak = 2.5
    stereo_offset = 0.10
    presetName$ = "Classic Wah"
elsif preset = 3
    modulation_mode = 1
    wah_rate = 3.5
    min_frequency = 350
    max_frequency = 2500
    bandwidth = 300
    resonance_peak = 3.0
    stereo_offset = 0.15
    presetName$ = "Funky Wah"
elsif preset = 4
    modulation_mode = 2
    min_frequency = 250
    max_frequency = 2200
    bandwidth = 400
    resonance_peak = 2.0
    stereo_offset = 0
    envelope_attack = 8
    envelope_release = 90
    envelope_range = 30
    presetName$ = "Auto-Wah"
elsif preset = 5
    modulation_mode = 1
    wah_rate = 1.2
    min_frequency = 500
    max_frequency = 2800
    bandwidth = 250
    resonance_peak = 4.0
    stereo_offset = 0.08
    presetName$ = "Crying Wah"
elsif preset = 6
    modulation_mode = 1
    wah_rate = 0.6
    min_frequency = 300
    max_frequency = 3500
    bandwidth = 500
    resonance_peak = 1.8
    stereo_offset = 0.20
    presetName$ = "Talk-Box-like Sweep"
elsif preset = 7
    modulation_mode = 1
    wah_rate = 0.4
    min_frequency = 500
    max_frequency = 1500
    bandwidth = 600
    resonance_peak = 1.5
    stereo_offset = 0.05
    presetName$ = "Subtle Sweep"
else
    presetName$ = "Custom"
endif

if modulation_mode = 1
    modulationName$ = "Sine LFO"
else
    modulationName$ = "Envelope Follower"
endif

# ============================================================
# INPUT VALIDATION / PARAMETER LIMITS
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
sampleRate = Get sampling frequency
nSrc = Get number of samples
numChannels = Get number of channels
xmin0 = Get start time
totalDuration = Get total duration
nyquist = sampleRate / 2

if totalDuration < 0.05
    exitScript: "Sound too short (minimum 0.05 s)."
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
endif
if wet_dry_percent > 100
    wet_dry_percent = 100
endif
wetAmt = wet_dry_percent / 100

if stereo_offset < 0
    stereo_offset = 0
endif
if stereo_offset > 0.5
    stereo_offset = 0.5
endif

if resonance_peak < 1
    resonance_peak = 1
endif
if resonance_peak > 12
    resonance_peak = 12
endif

if min_frequency > max_frequency
    tmpFreq = min_frequency
    min_frequency = max_frequency
    max_frequency = tmpFreq
endif
maxSafeFreq = max(20, nyquist - 2 * sampleRate / max(64, round(0.04 * sampleRate)))
if max_frequency > maxSafeFreq
    max_frequency = maxSafeFreq
endif
if min_frequency > max_frequency
    min_frequency = max(20, max_frequency * 0.5)
endif
if min_frequency < 20
    min_frequency = 20
endif
if bandwidth > nyquist * 1.5
    bandwidth = nyquist * 1.5
endif
if bandwidth < 20
    bandwidth = 20
endif

if envelope_attack < 0.1
    envelope_attack = 0.1
endif
if envelope_release < 0.1
    envelope_release = 0.1
endif
if envelope_range < 6
    envelope_range = 6
endif
if envelope_range > 80
    envelope_range = 80
endif

# ============================================================
# WORKING SOURCE / CHANNEL GEOMETRY
# ============================================================
selectObject: originalID
workSource = Copy: "wah_work"
selectObject: workSource
Shift times to: "start time", 0

if numChannels = 1
    outCh = 2
    channelNote$ = "mono -> stereo"
else
    outCh = numChannels
    channelNote$ = string$(numChannels) + " channels preserved"
endif

selectObject: workSource
if numChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "wah_analysis"
endif

# ============================================================
# STFT GEOMETRY
# ============================================================
nWin = round(0.04 * sampleRate)
if nWin < 64
    nWin = 64
endif
if (nWin mod 2) = 1
    nWin = nWin + 1
endif
hopN = round(nWin / 4)
if hopN < 1
    hopN = 1
endif
actualWindow_s = nWin / sampleRate
hop_s = hopN / sampleRate
binWidth = sampleRate / nWin
padN = nWin
padDur = padN / sampleRate

# Frame centers: 0, hop, 2hop, ... plus exact final center if needed.
gridFrames = floor(totalDuration / hop_s) + 1
lastGridCenter = (gridFrames - 1) * hop_s
extraEndFrame = 0
if totalDuration - lastGridCenter > 0.5 / sampleRate
    extraEndFrame = 1
endif
totalFrames = gridFrames + extraEndFrame

# ============================================================
# MODULATION TRAJECTORY
# ============================================================
if modulation_mode = 2
    # First pass: frame RMS, then map dB relative to the file maximum into 0..1.
    maxRMS = 0
    for f from 1 to totalFrames
        if f <= gridFrames
            centerTime = (f - 1) * hop_s
        else
            centerTime = totalDuration
        endif
        a1 = max(0, centerTime - actualWindow_s / 2)
        a2 = min(totalDuration, centerTime + actualWindow_s / 2)
        selectObject: analysisMono
        if a2 > a1
            thisRMS = Get root-mean-square: a1, a2
        else
            thisRMS = 0
        endif
        envRMS[f] = thisRMS
        if thisRMS > maxRMS
            maxRMS = thisRMS
        endif
    endfor

    if maxRMS <= 1e-15
        for f from 1 to totalFrames
            envRaw[f] = 0
            envSmooth[f] = 0
        endfor
    else
        for f from 1 to totalFrames
            rel = envRMS[f] / maxRMS
            if rel < 1e-12
                rel = 1e-12
            endif
            relDb = 20 * log10(rel)
            raw = (relDb + envelope_range) / envelope_range
            if raw < 0
                raw = 0
            endif
            if raw > 1
                raw = 1
            endif
            envRaw[f] = raw
        endfor

        attackTau = envelope_attack / 1000
        releaseTau = envelope_release / 1000
        attackCoef = 1 - exp(-hop_s / attackTau)
        releaseCoef = 1 - exp(-hop_s / releaseTau)
        envSmooth[1] = envRaw[1]
        for f from 2 to totalFrames
            if envRaw[f] > envSmooth[f-1]
                coef = attackCoef
            else
                coef = releaseCoef
            endif
            envSmooth[f] = envSmooth[f-1] + coef * (envRaw[f] - envSmooth[f-1])
        endfor
    endif
endif

# ============================================================
# REPORT
# ============================================================
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  WAH-WAH EFFECT v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Input: ", originalName$, " | ", fixed$(totalDuration, 3), " s | ", numChannels, " ch | ", fixed$(sampleRate, 0), " Hz | start ", fixed$(xmin0, 3)
appendInfoLine: "Output channels: ", channelNote$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Modulation: ", modulationName$
if modulation_mode = 1
    appendInfoLine: "LFO: ", fixed$(wah_rate, 3), " Hz | stereo offset ", fixed$(stereo_offset, 3), " cycles"
else
    appendInfoLine: "Envelope: attack ", fixed$(envelope_attack, 1), " ms | release ", fixed$(envelope_release, 1), " ms | range ", fixed$(envelope_range, 1), " dB"
endif
appendInfoLine: "Range: ", fixed$(min_frequency, 1), " - ", fixed$(max_frequency, 1), " Hz | BW ", fixed$(bandwidth, 1), " Hz"
appendInfoLine: "Resonance peak multiplier: ", fixed$(resonance_peak, 2)
appendInfoLine: "STFT: ", nWin, " samples (", fixed$(actualWindow_s * 1000, 2), " ms), hop ", fixed$(hop_s * 1000, 2), " ms, ", totalFrames, " frames"
appendInfoLine: "Wet: ", fixed$(wet_dry_percent, 1), "%"
appendInfoLine: ""

# ============================================================
# DRY-ONLY FAST PATH OR STFT WAH
# ============================================================
if wetAmt = 0
    selectObject: workSource
    if numChannels = 1
        outputSound = Convert to stereo
    else
        outputSound = Copy: "wah_output"
    endif
else
    outputSound = Create Sound from formula: "wah_output", outCh, 0, totalDuration, sampleRate, "0"
    weightBuffer = Create Sound from formula: "wah_weight", 1, 0, totalDuration, sampleRate, "0"

    # Analysis and synthesis windows are both sqrt-Hann. Their product is Hann.
    for f from 1 to totalFrames
        if f <= gridFrames
            centerTime = (f - 1) * hop_s
        else
            centerTime = totalDuration
        endif
        frameStart = centerTime - actualWindow_s / 2
        frameEnd = frameStart + actualWindow_s
        addStart = max(0, frameStart)
        addEnd = min(totalDuration, frameEnd)
        if addEnd > addStart
            selectObject: weightBuffer
            Formula (part): addStart, addEnd, 1, 1, "self + sin(pi * (x - frameStart) / actualWindow_s) ^ 2"
        endif
    endfor
    selectObject: weightBuffer
    wMax = Get maximum: 0, 0, "None"
    wMin = Get minimum: 0, 0, "None"
    wEps = max(1e-12, wMax * 1e-10)
    appendInfoLine: "OLA weight min/max: ", fixed$(wMin, 6), " / ", fixed$(wMax, 6)
    appendInfoLine: "Processing..."

    for ch from 1 to outCh
        if numChannels = 1
            srcCh = 1
        else
            srcCh = ch
        endif

        selectObject: workSource
        chan = Extract one channel: srcCh
        Rename: "wah_chan"
        pad = Create Sound from formula: "wah_pad", 1, 0, (nSrc + 2 * padN) / sampleRate, sampleRate,
            ... "if col > padN and col <= padN + nSrc then object[chan,1,col-padN] else 0 fi"

        if outCh > 1
            phaseOffset = stereo_offset * (ch - 1) / (outCh - 1)
        else
            phaseOffset = 0
        endif

        for f from 1 to totalFrames
            if f <= gridFrames
                centerTime = (f - 1) * hop_s
            else
                centerTime = totalDuration
            endif

            if modulation_mode = 1
                wahPos = 0.5 + 0.5 * sin(2 * pi * (wah_rate * centerTime + phaseOffset))
            else
                wahPos = envSmooth[f]
            endif
            centerFreq = min_frequency + wahPos * (max_frequency - min_frequency)

            lowEdge = max(0, centerFreq - bandwidth / 2)
            highEdge = min(nyquist, centerFreq + bandwidth / 2)
            transition = max(binWidth, bandwidth * 0.25)
            resWidth = max(binWidth, bandwidth * 0.18)

            frameStartPadded = padDur + centerTime - actualWindow_s / 2
            selectObject: pad
            frame = Extract part: frameStartPadded, frameStartPadded + actualWindow_s, "rectangular", 1, "no"
            Rename: "wah_frame"
            Formula: "self * sin(pi * (col - 0.5) / nWin)"

            selectObject: frame
            spec = To Spectrum: "no"

            lowStr$ = fixed$(lowEdge, 8)
            highStr$ = fixed$(highEdge, 8)
            transStr$ = fixed$(transition, 8)
            centerStr$ = fixed$(centerFreq, 8)
            resWidthStr$ = fixed$(resWidth, 8)
            resExtraStr$ = fixed$(resonance_peak - 1, 8)

            selectObject: spec
            Formula: "self * (if x < " + lowStr$ + " then if x <= " + lowStr$ + " - " + transStr$ + " then 0 else 0.5 - 0.5*cos(pi*(x-(" + lowStr$ + "-" + transStr$ + "))/" + transStr$ + ") fi else if x <= " + highStr$ + " then 1 else if x < " + highStr$ + " + " + transStr$ + " then 0.5 + 0.5*cos(pi*(x-" + highStr$ + ")/" + transStr$ + ") else 0 fi fi fi) * (1 + " + resExtraStr$ + " * exp(-0.5*((x-" + centerStr$ + ")/" + resWidthStr$ + ")^2))"

            selectObject: spec
            frameOut = To Sound
            Override sampling frequency: sampleRate
            Formula: "self * sin(pi * (col - 0.5) / nWin)"
            Rename: "wah_frameout"

            frameStart = centerTime - actualWindow_s / 2
            selectObject: frameOut
            Shift times to: "start time", frameStart
            frameEnd = frameStart + actualWindow_s
            addStart = max(0, frameStart)
            addEnd = min(totalDuration, frameEnd)
            if addEnd > addStart
                selectObject: outputSound
                Formula (part): addStart, addEnd, ch, ch, "self + Sound_wah_frameout(x)"
            endif

            removeObject: frame, spec, frameOut
        endfor

        removeObject: chan, pad
        appendInfoLine: "  channel ", ch, "/", outCh, " done"
    endfor

    selectObject: outputSound
    Formula: "if object[weightBuffer,1,col] > wEps then self / object[weightBuffer,1,col] else 0 fi"

    # Dry/wet mix. Mono dry is duplicated because the effect output is stereo.
    if wetAmt < 1
        selectObject: workSource
        if numChannels = 1
            dryRef = Convert to stereo
        else
            dryRef = Copy: "wah_dry"
        endif
        selectObject: outputSound
        Formula: "wetAmt * self + (1 - wetAmt) * object[dryRef,row,col]"
        removeObject: dryRef
    endif

    removeObject: weightBuffer
endif

# ============================================================
# SAFETY / TIME / NAMING
# ============================================================
selectObject: outputSound
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
safetyApplied = 0
if wetAmt > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Formula: "self * safety_peak / peakBeforeSafety"
    safetyApplied = 1
endif
peakFinal = Get absolute extremum: 0, 0, "None"

Shift times to: "start time", xmin0
Rename: originalName$ + "_wahwah"
outputName$ = selected$("Sound")

if safetyApplied
    appendInfoLine: "Safety attenuation: peak ", fixed$(peakBeforeSafety, 4), " -> ", fixed$(peakFinal, 4)
endif
appendInfoLine: "Output peak: ", fixed$(peakFinal, 4)
appendInfoLine: ""

# ============================================================
# VISUALIZATION (AudioTools house style)
# ============================================================
if draw_response
    selectObject: workSource
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "wah_viz_in"
    endif
    selectObject: outputSound
    resultMono = Convert to mono

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Title
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Wah-Wah Effect##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.22, "half", originalName$ + " | " + presetName$ + " | " + modulationName$

    # Input waveform
    Select outer viewport: 0, 8, 0.72, 1.52
    Select inner viewport: 0.55, 7.75, 0.80, 1.46
    selectObject: origMono
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.56, 2.36
    Select inner viewport: 0.55, 7.75, 1.64, 2.30
    selectObject: resultMono
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Frequency trajectory
    Select outer viewport: 0, 8, 2.44, 4.34
    Select inner viewport: 0.72, 7.70, 2.55, 4.25
    yMax = min(nyquist, max_frequency + bandwidth)
    if yMax <= min_frequency
        yMax = min(nyquist, min_frequency + 1000)
    endif
    Axes: 0, totalDuration, 0, yMax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, totalDuration, 0, yMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, min_frequency, totalDuration, min_frequency
    Draw line: 0, max_frequency, totalDuration, max_frequency

    trajPts = 240
    prevT = 0
    if modulation_mode = 1
        pL = 0.5 + 0.5 * sin(0)
        pR = 0.5 + 0.5 * sin(2*pi*stereo_offset)
        prevL = min_frequency + pL * (max_frequency - min_frequency)
        prevR = min_frequency + pR * (max_frequency - min_frequency)
        for q from 1 to trajPts
            tt = totalDuration * q / trajPts
            pL = 0.5 + 0.5 * sin(2*pi*wah_rate*tt)
            pR = 0.5 + 0.5 * sin(2*pi*(wah_rate*tt + stereo_offset))
            thisL = min_frequency + pL * (max_frequency - min_frequency)
            thisR = min_frequency + pR * (max_frequency - min_frequency)
            Colour: "{0.25, 0.50, 0.82}"
            Draw line: prevT, prevL, tt, thisL
            Colour: "{0.55, 0.40, 0.72}"
            Draw line: prevT, prevR, tt, thisR
            prevT = tt
            prevL = thisL
            prevR = thisR
        endfor
    else
        prevF = min_frequency + envSmooth[1] * (max_frequency - min_frequency)
        for f from 2 to totalFrames
            if f <= gridFrames
                tt = (f - 1) * hop_s
            else
                tt = totalDuration
            endif
            thisF = min_frequency + envSmooth[f] * (max_frequency - min_frequency)
            Colour: "{0.25, 0.50, 0.82}"
            Draw line: prevT, prevF, tt, thisF
            prevT = tt
            prevF = thisF
        endfor
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Center frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    if modulation_mode = 1
        Colour: "{0.25, 0.50, 0.82}"
        Text: totalDuration * 0.04, "left", yMax * 0.92, "half", "channel 1"
        Colour: "{0.55, 0.40, 0.72}"
        Text: totalDuration * 0.04, "left", yMax * 0.84, "half", "last channel / stereo offset"
    else
        Colour: "{0.35, 0.35, 0.52}"
        Text: totalDuration * 0.04, "left", yMax * 0.92, "half", "envelope follower"
    endif

    # Representative response at midpoint center
    Select outer viewport: 0, 8, 4.42, 5.66
    Select inner viewport: 0.72, 7.70, 4.52, 5.58
    repCenter = (min_frequency + max_frequency) / 2
    repLow = max(0, repCenter - bandwidth / 2)
    repHigh = min(nyquist, repCenter + bandwidth / 2)
    repTrans = max(binWidth, bandwidth * 0.25)
    repResWidth = max(binWidth, bandwidth * 0.18)
    respMax = max(1.2, resonance_peak * 1.1)
    Axes: 0, min(nyquist, max_frequency + 2*bandwidth), 0, respMax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, min(nyquist, max_frequency + 2*bandwidth), 0, respMax
    nResp = 260
    prevX = 0
    prevY = 0
    for q from 0 to nResp
        ff = min(nyquist, max_frequency + 2*bandwidth) * q / nResp
        if ff < repLow
            if ff <= repLow - repTrans
                bg = 0
            else
                bg = 0.5 - 0.5*cos(pi*(ff-(repLow-repTrans))/repTrans)
            endif
        elsif ff <= repHigh
            bg = 1
        elsif ff < repHigh + repTrans
            bg = 0.5 + 0.5*cos(pi*(ff-repHigh)/repTrans)
        else
            bg = 0
        endif
        yy = bg * (1 + (resonance_peak-1)*exp(-0.5*((ff-repCenter)/repResWidth)^2))
        if q > 0
            Colour: "{0.55, 0.40, 0.72}"
            Draw line: prevX, prevY, ff, yy
        endif
        prevX = ff
        prevY = yy
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Linear gain"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Representative response at midpoint center"

    # Summary
    Select outer viewport: 0, 8, 5.76, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.76, "half", "##Wah summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.35}"
    Text: 0.02, "left", 0.48, "half", "Range " + fixed$(min_frequency,0) + "-" + fixed$(max_frequency,0) + " Hz | BW " + fixed$(bandwidth,0) + " Hz | resonance x" + fixed$(resonance_peak,2) + " | wet " + fixed$(wet_dry_percent,0) + "%"
    Text: 0.02, "left", 0.20, "half", modulationName$ + " | " + channelNote$ + " | STFT " + fixed$(actualWindow_s*1000,1) + " ms / hop " + fixed$(hop_s*1000,1) + " ms | peak " + fixed$(peakFinal,4)

    Font size: 10
    Colour: "Black"
    Line width: 1
    removeObject: origMono, resultMono
endif

# ============================================================
# CLEANUP / OUTPUT
# ============================================================
removeObject: analysisMono, workSource
selectObject: outputSound
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", outputName$

if play_result
    Play
endif
