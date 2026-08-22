# ============================================================
# Praat AudioTools - The_Lucier_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 reviewed (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   The Lucier Machine - a Lucier-inspired iterative room-filter
#   process. A fixed synthetic room impulse response (direct path +
#   stochastic RT60-decaying reflections) is convolved repeatedly
#   with the input. Because the same transfer function is applied on
#   every pass, its resonant frequencies are progressively reinforced.
#
#   This is a digital model of repeated playback/re-record filtering,
#   not a geometrically exact physical room simulation.
#
# Review changes v0.3:
#   - Preserves stereo: a mono room IR filters every source channel.
#   - Reinterprets Mic proximity gain as the direct-path ENERGY share.
#   - Reflection energy is normalized independently of reflection count.
#     Number_of_reflections now controls density, not room/direct balance.
#   - Removes arbitrary IR peak normalization; IR discrete energy is 1.
#   - Re-aligns every iteration to the direct arrival, so pre-delay does
#     not accumulate and progressively crop the end of the source.
#   - Per-pass peak normalization is retained as recording-gain
#     stabilization, with one common gain for all stereo channels.
#   - Adds guards for pre-delay, iteration count, and normalization.
#   - Removes the meaningless peakHistory display (all peaks were forced
#     to the same normalization target).
#   - Visualization updated to the Praat AudioTools house style, with
#     the actual room transfer spectrum and final transformed spectrum.
#   - v0.3.1: redesigned visualization around the Lucier principle:
#     fixed room fingerprint H(f), repeated filtering, and H(f)^N.
#     Replaced the crowded bottom text summary with a process diagram.
#
# Review changes v0.4 (visualization only; the audio path is unchanged):
#   - The two spectrum panels could not be compared: independent dB
#     scales, no X_0, and the raw spectrum of a stochastic reflection
#     field drawn on a linear axis is an unreadable hair-line band. The
#     script therefore asserted its own claim in a caption without ever
#     showing it. Replaced by log-spaced band-averaged curves (Get band
#     density over 190 bands), with X_0 and X_N overlaid on one axis.
#   - Added an EMPHASIS PER PASS panel: the room's own shape against the
#     measured (X_N - X_0)/N. At one pass these coincide, which validates
#     the measurement. At 30 passes the measured emphasis is roughly half
#     the ideal. Two candidate causes, NOT yet separated: each pass is
#     truncated back to the source length, which discards exactly the
#     resonant ringing; and band averaging of a high power of a
#     stochastic spectrum is not the same as a high power of the band
#     average. The ratio is reported rather than explained away, and the
#     diagram now labels X_N = g_N X_0 H^N as the IDEAL form.
#   - Resonance markers are taken from the measured emphasis, not from
#     peaks of H(f) alone: what is audibly reinforced is the product of
#     source content and room shape, so H's own peaks can sit at
#     frequencies the source never excited.
#   - No panel had any axis numbers at all. All panels now carry marks.
#   - The process diagram was drawn at about half its requested height,
#     putting its title and caption outside the grey panel: text strips
#     used Select outer viewport, and Axes maps to the INNER viewport.
#     All text strips now use Select inner viewport.
#   - "Room energy 8%" printed as "Room energy 8": % is italic markup in
#     Picture-window text. All literal percent signs are now escaped.
#   - Waveform panels use explicit symmetric amplitude ranges instead of
#     relying on autoscaling, and stereo input is represented by its
#     loudest channel rather than a phase-destructive mono fold.
#   - Drawing-order rule established by testing: Text: and Draw inner box
#     both leave the drawing frame on the OUTER viewport, and a later
#     Axes: does NOT restore the inner one. Anything positioned in world
#     coordinates after them lands about 15 percent outside the panel.
#     Every panel therefore re-selects its inner viewport between the
#     annotation, curve and box groups.
# ============================================================

form The Lucier Machine
    comment Select a Sound object first (speech recommended)

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Lucier-style (30 iterations)
        option Quick Preview (10 iterations)
        option Extended Transformation (50 iterations)
        option Small Room (short RT60)
        option Large Hall (long RT60)

    comment === Room Acoustics ===
    positive IR_duration_s 1.5
    positive RT60_s 1.0
    natural Number_of_reflections 1000

    comment === Direct / Room Balance ===
    positive Pre_delay_s 0.01
    real Mic_proximity_gain 0.92
    comment (0..1; interpreted as direct-path energy share)
    comment (higher = slower transformation, lower = stronger room imprint)

    comment === Simulation ===
    natural Number_of_iterations 30
    positive Per_pass_peak_target 0.95
    comment (common gain stabilization after each virtual re-recording)

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT AND PRESET SETUP
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
originalStart = Get start time
sr = Get sampling frequency
numChannels = Get number of channels
nyquist = sr / 2

if numChannels <> 1 and numChannels <> 2
    exitScript: "The Lucier Machine currently supports mono or stereo Sound objects only."
endif

# === Apply Presets ===
if preset = 2
    # Lucier-style
    iR_duration_s = 1.5
    rT60_s = 1.0
    number_of_reflections = 1000
    pre_delay_s = 0.01
    mic_proximity_gain = 0.92
    number_of_iterations = 30
    per_pass_peak_target = 0.95
    presetName$ = "Lucier-style"
elsif preset = 3
    # Quick Preview
    iR_duration_s = 1.0
    rT60_s = 0.8
    number_of_reflections = 500
    pre_delay_s = 0.01
    mic_proximity_gain = 0.88
    number_of_iterations = 10
    per_pass_peak_target = 0.95
    presetName$ = "Quick"
elsif preset = 4
    # Extended Transformation
    iR_duration_s = 2.0
    rT60_s = 1.2
    number_of_reflections = 1500
    pre_delay_s = 0.012
    mic_proximity_gain = 0.94
    number_of_iterations = 50
    per_pass_peak_target = 0.95
    presetName$ = "Extended"
elsif preset = 5
    # Small Room
    iR_duration_s = 0.8
    rT60_s = 0.4
    number_of_reflections = 600
    pre_delay_s = 0.005
    mic_proximity_gain = 0.90
    number_of_iterations = 30
    per_pass_peak_target = 0.95
    presetName$ = "Small Room"
elsif preset = 6
    # Large Hall
    iR_duration_s = 3.0
    rT60_s = 2.5
    number_of_reflections = 2000
    pre_delay_s = 0.025
    mic_proximity_gain = 0.85
    number_of_iterations = 30
    per_pass_peak_target = 0.95
    presetName$ = "Large Hall"
else
    presetName$ = "Custom"
endif

# === Validate / clamp ===
if mic_proximity_gain < 0
    mic_proximity_gain = 0
elsif mic_proximity_gain > 1
    mic_proximity_gain = 1
endif

if per_pass_peak_target > 0.99
    per_pass_peak_target = 0.99
endif

if number_of_iterations > 100
    exitScript: "For stability and runtime, Number of iterations is limited to 100."
endif

if iR_duration_s <= 2 / sr
    exitScript: "IR duration is too short for the current sampling frequency."
endif

if pre_delay_s >= iR_duration_s - 1 / sr
    exitScript: "Pre-delay must be shorter than IR duration."
endif

directEnergyShare = mic_proximity_gain
reflectionEnergyShare = 1 - directEnergyShare
decayCoeff = 6.907755278982137 / rT60_s

# ============================================================
# INFO
# ============================================================

writeInfoLine: "=== The Lucier Machine ==="
appendInfoLine: "Lucier-inspired iterative room filtering"
appendInfoLine: ""
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Channels: ", numChannels
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Room:"
appendInfoLine: "  IR duration: ", fixed$(iR_duration_s, 3), " s"
appendInfoLine: "  RT60: ", fixed$(rT60_s, 3), " s"
appendInfoLine: "  Reflection density: ", number_of_reflections, " events"
appendInfoLine: "  Pre-delay: ", fixed$(pre_delay_s * 1000, 2), " ms"
appendInfoLine: "  Direct energy share: ", fixed$(100 * directEnergyShare, 1), "%"
appendInfoLine: "  Reflection energy share: ", fixed$(100 * reflectionEnergyShare, 1), "%"
appendInfoLine: ""
appendInfoLine: "Simulation:"
appendInfoLine: "  Iterations: ", number_of_iterations
appendInfoLine: "  Per-pass peak target: ", fixed$(per_pass_peak_target, 3)
appendInfoLine: ""

# ============================================================
# GENERATE FIXED ROOM IMPULSE RESPONSE
# ============================================================

appendInfoLine: "Generating fixed room impulse response..."

Create Sound from formula: "lucier_room_ir", 1, 0, iR_duration_s, sr, "0"
irSound = selected("Sound")
totalSamples = Get number of samples

# Generate only the stochastic reflection field first.
# The exponential amplitude envelope is -60 dB after one RT60.
if reflectionEnergyShare > 0
    for i from 1 to number_of_reflections
        # Keep random reflections at least one sample after the direct path.
        earliestReflection = pre_delay_s + 1 / sr
        availableReflectionTime = iR_duration_s - earliestReflection

        if availableReflectionTime > 0
            randTime = earliestReflection + randomUniform(0, availableReflectionTime)
            timeDelta = randTime - pre_delay_s
            naturalDecay = exp(-timeDelta * decayCoeff)
            amp = randomGauss(0, 1) * naturalDecay

            sampIdx = round(randTime * sr + 0.5)
            if sampIdx >= 1 and sampIdx <= totalSamples
                oldVal = Get value at sample number: 1, sampIdx
                Set value at sample number: 1, sampIdx, oldVal + amp
            endif
        endif
    endfor

    # Normalize reflection discrete energy to the requested room share.
    selectObject: irSound
    reflectionEnergy = Get energy: 0, 0

    if reflectionEnergy <= 0
        exitScript: "The generated reflection field has zero energy."
    endif

    # Get energy is sum(h^2)/sr for a sampled Sound. Therefore:
    # target discrete sum(h^2) = reflectionEnergyShare.
    reflectionGain = sqrt(reflectionEnergyShare / (reflectionEnergy * sr))
    reflection_gain_str$ = string$(reflectionGain)
    Formula: "self * " + reflection_gain_str$
endif

# Add direct arrival. sqrt(share) makes its squared coefficient equal
# to the requested direct-path energy share before final exact cleanup.
directSample = round(pre_delay_s * sr + 0.5)
if directSample < 1
    directSample = 1
elsif directSample > totalSamples
    directSample = totalSamples
endif

directAmp = sqrt(directEnergyShare)
selectObject: irSound
oldDirect = Get value at sample number: 1, directSample
Set value at sample number: 1, directSample, oldDirect + directAmp

# Exact unit discrete-energy normalization of the complete IR.
selectObject: irSound
irEnergy = Get energy: 0, 0
if irEnergy <= 0
    exitScript: "Generated room impulse response has zero energy."
endif

irGain = 1 / sqrt(irEnergy * sr)
ir_gain_str$ = string$(irGain)
Formula: "self * " + ir_gain_str$

appendInfoLine: "  Room IR generated and normalized."
appendInfoLine: ""

# ============================================================
# ITERATIVE PLAYBACK / RE-RECORD FILTERING
# ============================================================

appendInfoLine: "Starting iterative room filtering..."
appendInfoLine: ""

# Work on a copy; preserve stereo and shift the working time axis to zero.
selectObject: original
Copy: originalName$ + "_iteration_0"
currentSound = selected("Sound")

selectObject: currentSound
currentStart = Get start time
if currentStart <> 0
    Shift times by: -currentStart
endif

# Track gain compensation only for diagnostics / Info.
minGainDb = 1e30
maxGainDb = -1e30
sumGainDb = 0

for iteration from 1 to number_of_iterations
    appendInfoLine: "  Iteration ", iteration, " / ", number_of_iterations

    # Praat allows a multi-channel Sound to be convolved with a mono IR;
    # every channel is filtered by the same room transfer function.
    selectObject: currentSound, irSound
    Convolve: "sum", "zero"
    convolved = selected("Sound")

    # Re-align to the direct arrival. This prevents the propagation
    # pre-delay from accumulating over N iterations while preserving
    # all reflection delays relative to that arrival.
    selectObject: convolved
    extractStart = pre_delay_s
    extractEnd = pre_delay_s + originalDur
    Extract part: extractStart, extractEnd, "rectangular", 1, "no"
    rerecorded = selected("Sound")

    removeObject: currentSound, convolved

    # Recording-gain stabilization. Scale peak uses one common factor
    # across stereo channels, so the L/R relationship is preserved.
    selectObject: rerecorded
    prePeak = Get absolute extremum: 0, 0, "none"

    if prePeak <= 1e-15
        exitScript: "Signal collapsed to numerical silence during iteration " + string$(iteration) + "."
    endif

    gainFactor = per_pass_peak_target / prePeak
    gainDb = 20 * log10(gainFactor)

    if gainDb < minGainDb
        minGainDb = gainDb
    endif
    if gainDb > maxGainDb
        maxGainDb = gainDb
    endif
    sumGainDb = sumGainDb + gainDb

    Scale peak: per_pass_peak_target

    Rename: originalName$ + "_iteration_" + string$(iteration)
    currentSound = selected("Sound")
endfor

result = currentSound
Rename: originalName$ + "_lucier_" + presetName$

meanGainDb = sumGainDb / number_of_iterations

# ============================================================
# ============================================================
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ============================================================

# --- Drawing and analysis helpers (definitions are skipped at run time) ---

# Average power density over the pre-computed log-spaced bands.
# Praat can only draw a Spectrum on a LINEAR frequency axis, and the raw
# spectrum of a stochastic reflection field is an unreadable hair-line
# band. Band averaging supplies both the smoothing and the log axis that
# room resonances need.
procedure bandCurve: .spectrumId
    selectObject: .spectrumId
    for .b from 1 to nBands
        .d = Get band density: bandLoHz[.b], bandHiHz[.b]
        if .d = undefined or .d <= 0
            curve[.b] = undefined
        else
            curve[.b] = 10 * log10(.d)
        endif
    endfor
endproc

# Remove a curve's own mean level. Per-pass peak normalization is a
# scalar, so only the SHAPE of these curves carries meaning.
procedure centre
    .sum = 0
    .count = 0
    for .b from 1 to nBands
        if val[.b] <> undefined
            .sum = .sum + val[.b]
            .count = .count + 1
        endif
    endfor
    if .count > 0
        .mean = .sum / .count
    else
        .mean = 0
    endif
    for .b from 1 to nBands
        if val[.b] <> undefined
            val[.b] = val[.b] - .mean
        endif
    endfor
endproc

# Draw plot[] against the log-frequency axis, breaking the line
# wherever a value is undefined.
procedure plotCurve
    .penDown = 0
    for .b from 1 to nBands
        if plot[.b] <> undefined
            if .penDown = 1
                Draw line: bandMidLog[.b - 1], plot[.b - 1], bandMidLog[.b], plot[.b]
            endif
            .penDown = 1
        else
            .penDown = 0
        endif
    endfor
endproc

# .dense = 1 for full-width panels, 0 for the narrow pair (fewer labels,
# so that 500 and 1k do not collide).
# Marks left: N places marks AT the axis extremes, which produces values
# like 49.21 / -30.99. Choose a round step instead.
procedure niceMarksLeft: .lo, .hi
    .range = .hi - .lo
    if .range > 200
        .step = 50
    elsif .range > 90
        .step = 20
    elsif .range > 45
        .step = 10
    elsif .range > 18
        .step = 5
    elsif .range > 9
        .step = 2
    elsif .range > 4
        .step = 1
    else
        .step = 0.5
    endif
    Marks left every: 1, .step, "yes", "yes", "no"
endproc

procedure logMarks: .dense
    Font size: 5
    Colour: "Black"
    for .m from 1 to 8
        if .m = 1
            .f = 50
            .lab$ = "50"
        elsif .m = 2
            .f = 100
            .lab$ = "100"
        elsif .m = 3
            .f = 200
            .lab$ = "200"
        elsif .m = 4
            .f = 500
            .lab$ = "500"
        elsif .m = 5
            .f = 1000
            .lab$ = "1k"
        elsif .m = 6
            .f = 2000
            .lab$ = "2k"
        elsif .m = 7
            .f = 5000
            .lab$ = "5k"
        else
            .f = 10000
            .lab$ = "10k"
        endif
        .show = 1
        if .dense = 0 and (.m = 3 or .m = 6 or .m = 7)
            .show = 0
        endif
        if .show = 1 and .f >= vizFreqLo and .f <= vizFreqHi
            One mark bottom: log10(.f), "no", "yes", "no", .lab$
        endif
    endfor
endproc

procedure resonanceLines: .yLo, .yHi
    Line width: 1
    Dotted line
    Colour: "{0.55, 0.55, 0.62}"
    for .p from 1 to peakCount
        Draw line: bandMidLog[peakIdx[.p]], .yLo, bandMidLog[peakIdx[.p]], .yHi
    endfor
    Solid line
    Colour: "Black"
endproc

procedure arrow: .x1, .x2, .y
    Draw line: .x1, .y, .x2, .y
    Draw line: .x2, .y, .x2 - 0.013, .y + 0.040
    Draw line: .x2, .y, .x2 - 0.013, .y - 0.040
    Draw line: .x2 - 0.013, .y + 0.040, .x2 - 0.013, .y - 0.040
endproc

if draw_visualization
    appendInfoLine: "Building visualization..."

    # --------------------------------------------------------
    # Display material. A stereo signal is represented by its
    # loudest channel, not by a mono fold: summing channels is
    # phase-destructive and an anti-phase pair would vanish.
    # --------------------------------------------------------
    if numChannels = 2
        selectObject: original
        Extract one channel: 1
        vizCandL = selected("Sound")
        vizPeakL = Get absolute extremum: 0, 0, "none"

        selectObject: original
        Extract one channel: 2
        vizCandR = selected("Sound")
        vizPeakR = Get absolute extremum: 0, 0, "none"

        if vizPeakR > vizPeakL
            vizChannel = 2
            vizSrcMono = vizCandR
            removeObject: vizCandL
        else
            vizChannel = 1
            vizSrcMono = vizCandL
            removeObject: vizCandR
        endif

        selectObject: result
        Extract one channel: vizChannel
        vizFinalMono = selected("Sound")

        channelLabel$ = "stereo, channel " + string$(vizChannel) + " shown"
    else
        vizChannel = 1

        selectObject: original
        Copy: "viz_source"
        vizSrcMono = selected("Sound")

        selectObject: result
        Copy: "viz_final"
        vizFinalMono = selected("Sound")

        channelLabel$ = "mono"
    endif

    # Underscore is SUBSCRIPT markup in Picture-window text.
    vizName$ = replace$(originalName$, "_", "-", 0)

    selectObject: vizSrcMono
    To Spectrum: "yes"
    srcSpectrum = selected("Spectrum")

    selectObject: vizFinalMono
    To Spectrum: "yes"
    finalSpectrum = selected("Spectrum")

    selectObject: irSound
    To Spectrum: "yes"
    irSpectrum = selected("Spectrum")

    # --------------------------------------------------------
    # Log-spaced band geometry
    # --------------------------------------------------------
    nBands = 190
    vizFreqLo = 40
    vizFreqHi = min(16000, 0.95 * nyquist)

    logLo = log10(vizFreqLo)
    logHi = log10(vizFreqHi)
    logStep = (logHi - logLo) / nBands

    # A band narrower than about two FFT bins cannot be measured, so the
    # lowest bands are widened to the resolution of the coarser spectrum.
    minBandHz = 2 / min(originalDur, iR_duration_s)

    for b from 1 to nBands
        bandLoLog[b] = logLo + (b - 1) * logStep
        bandHiLog[b] = logLo + b * logStep
        bandMidLog[b] = (bandLoLog[b] + bandHiLog[b]) / 2

        bLo = 10 ^ bandLoLog[b]
        bHi = 10 ^ bandHiLog[b]
        if bHi - bLo < minBandHz
            bMid = (bLo + bHi) / 2
            bLo = bMid - minBandHz / 2
            bHi = bMid + minBandHz / 2
            if bLo < 0
                bLo = 0
                bHi = minBandHz
            endif
        endif
        bandLoHz[b] = bLo
        bandHiHz[b] = bHi
    endfor

    @bandCurve: srcSpectrum
    for b from 1 to nBands
        val[b] = curve[b]
    endfor
    @centre
    for b from 1 to nBands
        x0Db[b] = val[b]
    endfor

    @bandCurve: finalSpectrum
    for b from 1 to nBands
        val[b] = curve[b]
    endfor
    @centre
    for b from 1 to nBands
        xnDb[b] = val[b]
    endfor

    @bandCurve: irSpectrum
    for b from 1 to nBands
        val[b] = curve[b]
    endfor
    @centre
    for b from 1 to nBands
        hDb[b] = val[b]
    endfor

    # Emphasis per pass, in dB. Model = the room's own transfer shape.
    # Measurement = the total change over N passes divided by N. Only
    # bands where the SOURCE had energy can be measured; elsewhere the
    # difference is numerical floor and the curve is broken, not drawn.
    x0Max = -1e30
    for b from 1 to nBands
        if x0Db[b] <> undefined and x0Db[b] > x0Max
            x0Max = x0Db[b]
        endif
    endfor
    measFloorDb = x0Max - 55

    for b from 1 to nBands
        if x0Db[b] <> undefined and xnDb[b] <> undefined and x0Db[b] > measFloorDb
            measDb[b] = (xnDb[b] - x0Db[b]) / number_of_iterations
        else
            measDb[b] = undefined
        endif
    endfor

    # How closely the realized process follows the ideal H(f)^N. At one
    # pass this is essentially 1. It falls at higher N: each pass is
    # truncated back to the source length, and band averaging of a
    # high power of a stochastic spectrum is not the same as a high
    # power of the band average. Reported rather than explained away.
    modSumSq = 0
    meaSumSq = 0
    agreeCount = 0
    for b from 1 to nBands
        if measDb[b] <> undefined and hDb[b] <> undefined
            modSumSq = modSumSq + hDb[b] * hDb[b]
            meaSumSq = meaSumSq + measDb[b] * measDb[b]
            agreeCount = agreeCount + 1
        endif
    endfor
    if agreeCount > 0 and modSumSq > 0
        emphasisRatio = sqrt(meaSumSq / modSumSq)
        emphasisRatio$ = fixed$(emphasisRatio, 2)
    else
        emphasisRatio = undefined
        emphasisRatio$ = "n/a"
    endif

    # --------------------------------------------------------
    # Room resonance peaks, taken from the room curve itself.
    # These are the frequencies the process reinforces.
    # --------------------------------------------------------
    hSumSq = 0
    hCount = 0
    for b from 1 to nBands
        if measDb[b] <> undefined
            hSumSq = hSumSq + measDb[b] * measDb[b]
            hCount = hCount + 1
        endif
    endfor
    if hCount > 0
        hSd = sqrt(hSumSq / hCount)
    else
        hSd = 0
    endif

    # Peaks are taken from the MEASURED emphasis, not from H(f) alone.
    # What the listener hears reinforced is the product of source content
    # and room shape, so the peaks of H by itself can sit at frequencies
    # the source never excited. Searched on a lightly smoothed copy,
    # because the raw curve is a stochastic field and a single noisy
    # low-frequency band would otherwise win.
    for b from 1 to nBands
        if measDb[b] = undefined
            hSm[b] = undefined
        elsif b = 1 or b = nBands
            hSm[b] = measDb[b]
        elsif measDb[b - 1] <> undefined and measDb[b + 1] <> undefined
            hSm[b] = (measDb[b - 1] + measDb[b] + measDb[b + 1]) / 3
        else
            hSm[b] = measDb[b]
        endif
    endfor

    peakCount = 0
    maxPeaks = 4
    peakHalfWindow = 8
    minPeakSeparation = 16

    for peakPass from 1 to maxPeaks
        bestVal = -1e30
        bestIdx = 0

        for b from peakHalfWindow + 1 to nBands - peakHalfWindow
            if hSm[b] <> undefined and hSm[b] > 0.8 * hSd
                isLocalMax = 1
                for k from -peakHalfWindow to peakHalfWindow
                    if k <> 0 and hSm[b + k] <> undefined and hSm[b + k] > hSm[b]
                        isLocalMax = 0
                    endif
                endfor

                if isLocalMax = 1
                    tooClose = 0
                    for p from 1 to peakCount
                        if abs(b - peakIdx[p]) < minPeakSeparation
                            tooClose = 1
                        endif
                    endfor

                    if tooClose = 0 and hSm[b] > bestVal
                        bestVal = hSm[b]
                        bestIdx = b
                    endif
                endif
            endif
        endfor

        if bestIdx > 0
            peakCount = peakCount + 1
            peakIdx[peakCount] = bestIdx
            peakHz[peakCount] = 10 ^ bandMidLog[bestIdx]
        endif
    endfor

    for i from 1 to peakCount - 1
        for j from 1 to peakCount - i
            if peakHz[j] > peakHz[j + 1]
                tmpHz = peakHz[j]
                peakHz[j] = peakHz[j + 1]
                peakHz[j + 1] = tmpHz
                tmpIdx = peakIdx[j]
                peakIdx[j] = peakIdx[j + 1]
                peakIdx[j + 1] = tmpIdx
            endif
        endfor
    endfor

    peakList$ = ""
    for p from 1 to peakCount
        if p > 1
            peakList$ = peakList$ + ", "
        endif
        if peakHz[p] >= 1000
            peakList$ = peakList$ + fixed$(peakHz[p] / 1000, 2) + " kHz"
        else
            peakList$ = peakList$ + fixed$(peakHz[p], 0) + " Hz"
        endif
    endfor
    if peakCount = 0
        peakList$ = "none above threshold"
    endif

    # --------------------------------------------------------
    # Canvas
    # --------------------------------------------------------
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Solid line
    Line width: 1

    # Title strip. Text strips use INNER viewports, because Axes maps to
    # the inner viewport: a short OUTER viewport is inset by the standard
    # margins and the strip comes out about half the height requested.
    Select inner viewport: 0.60, 7.70, 0.12, 0.46
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.78, "half", "##THE LUCIER MACHINE##" + " | v0.5.1"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.20, "half",
        ... vizName$ + "  |  " + presetName$ + "  |  " + string$(number_of_iterations)
        ... + " passes  |  RT60 " + fixed$(rT60_s, 2) + " s  |  room energy "
        ... + fixed$(100 * reflectionEnergyShare, 0) + "\%   |  " + channelLabel$

    # --------------------------------------------------------
    # Time domain. Explicit symmetric amplitude ranges, so the drawn
    # height is a known quantity rather than whatever autoscaling gave.
    # --------------------------------------------------------
    selectObject: vizSrcMono
    srcPeak = Get absolute extremum: 0, 0, "none"
    if srcPeak <= 0
        srcPeak = 1
    endif

    selectObject: vizFinalMono
    finPeak = Get absolute extremum: 0, 0, "none"
    if finPeak <= 0
        finPeak = 1
    endif

    Select inner viewport: 0.60, 7.70, 0.66, 1.18
    selectObject: vizSrcMono
    Colour: "{0.62, 0.62, 0.62}"
    Draw: 0, 0, -srcPeak, srcPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.66, 1.18
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Original"
    Select inner viewport: 0.60, 7.70, 0.66, 1.18
    Axes: 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 1.28, 1.80
    selectObject: vizFinalMono
    Colour: "{0.72, 0.45, 0.42}"
    Draw: 0, originalDur, -finPeak, finPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 1.28, 1.80
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Pass " + string$(number_of_iterations)
    Select inner viewport: 0.60, 7.70, 1.28, 1.80
    Axes: 0, 1, 0, 1
    # Peak figures live in the summary bar rather than as corner text:
    # after Draw the world frame is seconds by amplitude, and mixing that
    # with fractional placement is how labels end up outside the box.
    Axes: 0, originalDur, 0, 1
    Font size: 6
    Colour: "Black"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"

    # --------------------------------------------------------
    # Before against after, on ONE axis. This is the panel that has to
    # carry the argument, so both curves share a scale and the room's
    # own resonances are marked across them.
    # --------------------------------------------------------
    Select inner viewport: 0.60, 7.70, 2.12, 2.30
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##SPECTRUM BEFORE AND AFTER##"

    yMin = 1e30
    yMax = -1e30
    for b from 1 to nBands
        if x0Db[b] <> undefined
            if x0Db[b] < yMin
                yMin = x0Db[b]
            endif
            if x0Db[b] > yMax
                yMax = x0Db[b]
            endif
        endif
        if xnDb[b] <> undefined
            if xnDb[b] < yMin
                yMin = xnDb[b]
            endif
            if xnDb[b] > yMax
                yMax = xnDb[b]
            endif
        endif
    endfor
    if yMin < -80
        yMin = -80
    endif
    yPad = 0.08 * (yMax - yMin)
    specLo = yMin - yPad
    specHi = yMax + yPad

    Select inner viewport: 0.60, 7.70, 2.46, 3.60
    Axes: logLo, logHi, specLo, specHi
    Paint rectangle: "{0.97, 0.97, 0.99}", logLo, logHi, specLo, specHi

    # In-panel annotation is drawn immediately after `Paint rectangle`,
    # before the curves. Both `Text:` and `Draw inner box` leave the
    # drawing frame on the OUTER viewport, and a later `Axes:` does not
    # restore the inner one: text placed after them lands about 15 percent
    # outside the panel, and a box drawn after them comes out oversized.
    # Hence also the re-select of the inner viewport before each box.
    Line width: 1
    Font size: 6
    Colour: "{0.55, 0.55, 0.55}"
    Text: logHi - 0.035 * (logHi - logLo), "right", specHi - 0.13 * (specHi - specLo),
        ... "half", "original"
    Colour: "{0.72, 0.45, 0.42}"
    Text: logHi - 0.035 * (logHi - logLo), "right", specHi - 0.25 * (specHi - specLo),
        ... "half", "after " + string$(number_of_iterations) + " passes"
    Colour: "{0.45, 0.45, 0.52}"
    Text: logLo + 0.025 * (logHi - logLo), "left", specLo + 0.13 * (specHi - specLo),
        ... "half", "dotted lines: frequencies the process actually reinforced"


    # Re-anchor: the Text block above left the frame on the outer viewport.
    Select inner viewport: 0.60, 7.70, 2.46, 3.60
    Axes: logLo, logHi, specLo, specHi
    @resonanceLines: specLo, specHi

    Line width: 1
    Colour: "{0.62, 0.62, 0.62}"
    for b from 1 to nBands
        plot[b] = x0Db[b]
    endfor
    @plotCurve

    Line width: 1.5
    Colour: "{0.72, 0.45, 0.42}"
    for b from 1 to nBands
        plot[b] = xnDb[b]
    endfor
    @plotCurve

    Select inner viewport: 0.60, 7.70, 2.46, 3.60
    Axes: logLo, logHi, specLo, specHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    @niceMarksLeft: specLo, specHi
    @logMarks: 1
    Font size: 6
    Text bottom: "yes", "Frequency (Hz)"
    Select inner viewport: 0.20, 0.48, 2.46, 3.60
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Level (dB, mean removed)"
    Select inner viewport: 0.60, 7.70, 2.46, 3.60
    Axes: logLo, logHi, specLo, specHi

    # --------------------------------------------------------
    # Lower pair: the room's own shape, and the emphasis it produces
    # per pass, model against measurement.
    # --------------------------------------------------------
    Select inner viewport: 0.60, 3.98, 3.94, 4.12
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##ROOM FINGERPRINT H(f)##"

    Select inner viewport: 4.32, 7.70, 3.94, 4.12
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##EMPHASIS PER PASS##"

    hMin = 1e30
    hMax = -1e30
    for b from 1 to nBands
        if hDb[b] <> undefined
            if hDb[b] < hMin
                hMin = hDb[b]
            endif
            if hDb[b] > hMax
                hMax = hDb[b]
            endif
        endif
    endfor
    hPad = 0.12 * (hMax - hMin)
    hLo = hMin - hPad
    hHi = hMax + hPad

    Select inner viewport: 0.60, 3.98, 4.28, 5.22
    Axes: logLo, logHi, hLo, hHi
    Paint rectangle: "{0.97, 0.97, 0.99}", logLo, logHi, hLo, hHi

    Line width: 1
    Font size: 6
    Colour: "{0.45, 0.45, 0.52}"
    Text: logLo + 0.06 * (logHi - logLo), "left", hLo + 0.14 * (hHi - hLo), "half",
        ... "ripple raised to the power " + string$(number_of_iterations)

    Select inner viewport: 0.60, 3.98, 4.28, 5.22
    Axes: logLo, logHi, hLo, hHi
    @resonanceLines: hLo, hHi

    Line width: 1.5
    Colour: "{0.46, 0.60, 0.74}"
    for b from 1 to nBands
        plot[b] = hDb[b]
    endfor
    @plotCurve

    Select inner viewport: 0.60, 3.98, 4.28, 5.22
    Axes: logLo, logHi, hLo, hHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    @niceMarksLeft: hLo, hHi
    @logMarks: 0
    Font size: 6
    Text bottom: "yes", "Frequency (Hz)"
    Select inner viewport: 0.20, 0.48, 4.28, 5.22
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "dB"
    Select inner viewport: 0.60, 3.98, 4.28, 5.22
    Axes: logLo, logHi, hLo, hHi

    eMin = 1e30
    eMax = -1e30
    for b from 1 to nBands
        if hDb[b] <> undefined
            if hDb[b] < eMin
                eMin = hDb[b]
            endif
            if hDb[b] > eMax
                eMax = hDb[b]
            endif
        endif
        if measDb[b] <> undefined
            if measDb[b] < eMin
                eMin = measDb[b]
            endif
            if measDb[b] > eMax
                eMax = measDb[b]
            endif
        endif
    endfor
    ePad = 0.12 * (eMax - eMin)
    eLo = eMin - ePad
    eHi = eMax + ePad

    Select inner viewport: 4.32, 7.70, 4.28, 5.22
    Axes: logLo, logHi, eLo, eHi
    Paint rectangle: "{0.97, 0.97, 0.99}", logLo, logHi, eLo, eHi

    Line width: 1
    Font size: 6
    Colour: "{0.46, 0.60, 0.74}"
    Text: logLo + 0.03 * (logHi - logLo), "left", eHi - 0.10 * (eHi - eLo), "half",
        ... "ideal  H(f)"
    Colour: "{0.72, 0.45, 0.42}"
    Text: logLo + 0.03 * (logHi - logLo), "left", eHi - 0.21 * (eHi - eLo), "half",
        ... "measured  (X_N \-- X_0) / N"
    Colour: "{0.45, 0.45, 0.52}"
    Text: logHi - 0.03 * (logHi - logLo), "right", eLo + 0.10 * (eHi - eLo), "half",
        ... "measured / ideal = " + emphasisRatio$

    Select inner viewport: 4.32, 7.70, 4.28, 5.22
    Axes: logLo, logHi, eLo, eHi
    @resonanceLines: eLo, eHi

    Line width: 1
    Colour: "{0.46, 0.60, 0.74}"
    for b from 1 to nBands
        plot[b] = hDb[b]
    endfor
    @plotCurve

    Line width: 1.5
    Colour: "{0.72, 0.45, 0.42}"
    for b from 1 to nBands
        plot[b] = measDb[b]
    endfor
    @plotCurve

    Select inner viewport: 4.32, 7.70, 4.28, 5.22
    Axes: logLo, logHi, eLo, eHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    @niceMarksLeft: eLo, eHi
    @logMarks: 0
    Font size: 6
    Text bottom: "yes", "Frequency (Hz)"
    Select inner viewport: 3.92, 4.20, 4.28, 5.22
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "dB per pass"
    Select inner viewport: 4.32, 7.70, 4.28, 5.22
    Axes: logLo, logHi, eLo, eHi

    # --------------------------------------------------------
    # Process diagram
    # --------------------------------------------------------
    Select inner viewport: 0.60, 7.70, 5.68, 6.46
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    Colour: "Black"
    Font size: 7
    Text: 0.5, "centre", 0.88, "half",
        ... "##REPEATED FILTERING THROUGH ONE FIXED ROOM \--  "
        ... + string$(number_of_iterations) + " PASSES##"

    boxLo = 0.45
    boxHi = 0.73

    Paint rectangle: "{0.90, 0.90, 0.90}", 0.020, 0.150, boxLo, boxHi
    Paint rectangle: "{0.86, 0.91, 0.96}", 0.225, 0.355, boxLo, boxHi
    Paint rectangle: "{0.93, 0.93, 0.93}", 0.425, 0.575, boxLo, boxHi
    Paint rectangle: "{0.86, 0.91, 0.96}", 0.645, 0.775, boxLo, boxHi
    Paint rectangle: "{0.96, 0.88, 0.86}", 0.850, 0.980, boxLo, boxHi

    Colour: "Black"
    Line width: 1
    Draw rectangle: 0.020, 0.150, boxLo, boxHi
    Draw rectangle: 0.225, 0.355, boxLo, boxHi
    Draw rectangle: 0.425, 0.575, boxLo, boxHi
    Draw rectangle: 0.645, 0.775, boxLo, boxHi
    Draw rectangle: 0.850, 0.980, boxLo, boxHi

    Font size: 6
    Text: 0.085, "centre", 0.59, "half", "SOURCE"
    Text: 0.290, "centre", 0.65, "half", "ROOM"
    Text: 0.290, "centre", 0.53, "half", "H(f)"
    Text: 0.500, "centre", 0.65, "half", "LEVEL"
    Text: 0.500, "centre", 0.53, "half", "STABILIZE"
    Text: 0.710, "centre", 0.65, "half", "ROOM"
    Text: 0.710, "centre", 0.53, "half", "H(f)"
    Text: 0.915, "centre", 0.59, "half", "OUTPUT"

    arrowY = 0.59
    @arrow: 0.150, 0.225, arrowY
    @arrow: 0.355, 0.425, arrowY
    @arrow: 0.575, 0.645, arrowY
    @arrow: 0.775, 0.850, arrowY

    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.5, "centre", 0.28, "half", "X_N(f)  =  g_N \.c X_0(f) \.c H(f)^N"

    Font size: 6
    Colour: "{0.42, 0.42, 0.42}"
    Text: 0.5, "centre", 0.11, "half",
        ... "The level stabilizer g is a single scalar, so it cannot change spectral "
        ... + "shape. Only H(f)^N does."
    Text: 0.5, "centre", 0.02, "half",
        ... "Ideal form. Each pass is also truncated back to the source length, so the "
        ... + "realized emphasis is weaker \-- see EMPHASIS PER PASS."

    # --------------------------------------------------------
    # Summary bar
    # --------------------------------------------------------
    Select outer viewport: 0, 8, 6.53, 7.53
    Select inner viewport: 0.60, 7.70, 6.60, 7.46
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Line width: 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.84, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.60, "half", 
        ... "Room:  IR " + fixed$(iR_duration_s, 2) + " s  |  RT60 "
        ... + fixed$(rT60_s, 2) + " s  |  " + string$(number_of_reflections)
        ... + " reflections  |  pre-delay " + fixed$(pre_delay_s * 1000, 1)
        ... + " ms  |  direct " + fixed$(100 * directEnergyShare, 0)
        ... + "\%  / room " + fixed$(100 * reflectionEnergyShare, 0) + "\%  energy"
    Font size: 6
    Text: 0.02, "left", 0.37, "half", 
        ... "Process:  " + string$(number_of_iterations)
        ... + " passes  |  per-pass peak target " + fixed$(per_pass_peak_target, 2)
        ... + "  |  peak " + fixed$(srcPeak, 3) + " in, " + fixed$(finPeak, 3)
        ... + " out  |  mean gain compensation " + fixed$(meanGainDb, 2)
        ... + " dB (range " + fixed$(minGainDb, 2) + " to "
        ... + fixed$(maxGainDb, 2) + " dB)"
    Font size: 6
    Text: 0.02, "left", 0.13, "half", 
        ... "Resonances reinforced:  " + peakList$
        ... + "     |     measured / ideal emphasis " + emphasisRatio$
        ... + "     |     display " + fixed$(vizFreqLo, 0) + " Hz to "
        ... + fixed$(vizFreqHi / 1000, 1) + " kHz, logarithmic, "
        ... + string$(nBands) + " bands"

    Select inner viewport: 0.60, 7.70, 6.60, 7.46
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: irSpectrum, srcSpectrum, finalSpectrum
    removeObject: vizSrcMono, vizFinalMono

    appendInfoLine: "  Room resonances detected: ", peakList$
    appendInfoLine: "  Measured / ideal emphasis: ", emphasisRatio$
    appendInfoLine: ""

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 7.63
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEANUP / FINAL INFO / PLAY
# ============================================================

removeObject: irSound

selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "none"

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Final duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
appendInfoLine: "Mean per-pass gain compensation: ", fixed$(meanGainDb, 2), " dB"
appendInfoLine: "Gain compensation range: ", fixed$(minGainDb, 2), " to ", fixed$(maxGainDb, 2), " dB"

if directEnergyShare = 1
    appendInfoLine: ""
    appendInfoLine: "NOTE: Direct energy is 100%, so no room resonances are present."
endif

if play_result
    selectObject: result
    Play
endif

selectObject: result
