# ============================================================
# Praat AudioTools - The_Lucier_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.1 reviewed (2026)
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
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ============================================================

if draw_visualization
    # Create spectra used only for visualization.
    selectObject: irSound
    To Spectrum: "yes"
    irSpectrum = selected("Spectrum")

    if numChannels = 2
        selectObject: result
        Convert to mono
        vizFinalMono = selected("Sound")

        selectObject: vizFinalMono
        To Spectrum: "yes"
        finalSpectrum = selected("Spectrum")
    else
        selectObject: result
        To Spectrum: "yes"
        finalSpectrum = selected("Spectrum")
    endif

    Erase all

    # --------------------------------------------------------
    # Header
    # --------------------------------------------------------
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "The Lucier Machine | " + presetName$

    Select outer viewport: 0, 8, 0.36, 0.60
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.55, "half", originalName$ + " | " + string$(number_of_iterations) + " passes | RT60 " + fixed$(rT60_s, 2) + " s | Room energy " + fixed$(100 * reflectionEnergyShare, 0) + "%"

    # --------------------------------------------------------
    # Time domain: before / after
    # --------------------------------------------------------
    Select outer viewport: 0, 8, 0.68, 1.34
    Select inner viewport: 0.68, 7.66, 0.75, 1.27
    selectObject: original
    Colour: "{0.66, 0.66, 0.66}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Original"

    Select outer viewport: 0, 8, 1.41, 2.07
    Select inner viewport: 0.68, 7.66, 1.48, 2.00
    selectObject: result
    Colour: "{0.70, 0.48, 0.45}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pass " + string$(number_of_iterations)
    Text bottom: "yes", "Time (s)"

    # --------------------------------------------------------
    # Spectral principle: fixed fingerprint -> transformed result
    # --------------------------------------------------------
    displayMaxHz = min(12000, nyquist)

    Select outer viewport: 0.15, 3.95, 2.34, 3.77
    Select inner viewport: 0.62, 3.70, 2.60, 3.58
    selectObject: irSpectrum
    Colour: "{0.46, 0.60, 0.74}"
    Draw: 0, displayMaxHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB/Hz"
    Text bottom: "yes", "Frequency (Hz)"

    Select outer viewport: 0.15, 3.95, 2.18, 2.43
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "ROOM FINGERPRINT  H(f)"

    Select outer viewport: 4.05, 7.85, 2.34, 3.77
    Select inner viewport: 4.48, 7.62, 2.60, 3.58
    selectObject: finalSpectrum
    Colour: "{0.72, 0.45, 0.42}"
    Draw: 0, displayMaxHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB/Hz"
    Text bottom: "yes", "Frequency (Hz)"

    Select outer viewport: 4.05, 7.85, 2.18, 2.43
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "AFTER " + string$(number_of_iterations) + " PASSES"

    # --------------------------------------------------------
    # Principle diagram: repeated filtering through the SAME room
    # --------------------------------------------------------
    Select outer viewport: 0.35, 7.65, 3.88, 4.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955, 0.955, 0.955}", 0, 1, 0, 1

    # Panel title.
    Colour: "Black"
    Font size: 8
    Text: 0.5, "centre", 0.88, "half", "REPEATED FILTERING THROUGH ONE FIXED ROOM"

    # Process boxes.
    Paint rectangle: "{0.90, 0.90, 0.90}", 0.035, 0.17, 0.43, 0.69
    Paint rectangle: "{0.86, 0.91, 0.96}", 0.245, 0.39, 0.43, 0.69
    Paint rectangle: "{0.92, 0.92, 0.92}", 0.455, 0.56, 0.43, 0.69
    Paint rectangle: "{0.86, 0.91, 0.96}", 0.625, 0.77, 0.43, 0.69
    Paint rectangle: "{0.96, 0.88, 0.86}", 0.835, 0.965, 0.43, 0.69

    Colour: "Black"
    Line width: 1
    Draw rectangle: 0.035, 0.17, 0.43, 0.69
    Draw rectangle: 0.245, 0.39, 0.43, 0.69
    Draw rectangle: 0.455, 0.56, 0.43, 0.69
    Draw rectangle: 0.625, 0.77, 0.43, 0.69
    Draw rectangle: 0.835, 0.965, 0.43, 0.69

    Font size: 6
    Text: 0.1025, "centre", 0.56, "half", "SOURCE"
    Text: 0.3175, "centre", 0.585, "half", "ROOM"
    Text: 0.3175, "centre", 0.505, "half", "H(f)"
    Text: 0.5075, "centre", 0.585, "half", "LEVEL"
    Text: 0.5075, "centre", 0.505, "half", "STABILIZE"
    Text: 0.6975, "centre", 0.585, "half", "ROOM"
    Text: 0.6975, "centre", 0.505, "half", "H(f)"
    Text: 0.9000, "centre", 0.56, "half", "OUTPUT"

    # Connection lines and small triangular arrowheads.
    Draw line: 0.17, 0.56, 0.245, 0.56
    Draw line: 0.39, 0.56, 0.455, 0.56
    Draw line: 0.56, 0.56, 0.625, 0.56
    Draw line: 0.77, 0.56, 0.835, 0.56

    Draw line: 0.245, 0.56, 0.233, 0.585
    Draw line: 0.245, 0.56, 0.233, 0.535
    Draw line: 0.455, 0.56, 0.443, 0.585
    Draw line: 0.455, 0.56, 0.443, 0.535
    Draw line: 0.625, 0.56, 0.613, 0.585
    Draw line: 0.625, 0.56, 0.613, 0.535
    Draw line: 0.835, 0.56, 0.823, 0.585
    Draw line: 0.835, 0.56, 0.823, 0.535

    # Ellipsis / repetition cue.
    Font size: 8
    Text: 0.594, "centre", 0.56, "half", "..."

    # The key relation. Per-pass gain is scalar, so it does not alter
    # the spectral ratios created by repeated multiplication by H(f).
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.5, "centre", 0.245, "half", "X_N(f)  proportional to  X_0(f) * H(f)^N"

    Font size: 5
    Colour: "{0.42, 0.42, 0.42}"
    Text: 0.5, "centre", 0.095, "half", "The same room fingerprint is applied every pass; its resonant peaks are progressively reinforced."

    Font size: 10
    Colour: "Black"

    removeObject: irSpectrum, finalSpectrum
    if numChannels = 2
        removeObject: vizFinalMono
    endif
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
