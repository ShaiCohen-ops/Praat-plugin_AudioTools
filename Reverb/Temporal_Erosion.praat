# ============================================================
# Praat AudioTools - Temporal_Erosion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 reviewed (2026)
# v0.4.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Temporal Erosion - convolution reverb based on a dense Poisson
#   impulse response, a logarithmic decay envelope, and bounded
#   sample-wise Gaussian amplitude roughening. The logarithmic
#   envelope drops quickly at first and then decays more gradually.
#
# Review changes v0.3:
#   - Corrected wet/dry reads to documented time-based object().
#   - Fade is applied to the wet tail before wet/dry mixing.
#   - Removed output/per-channel peak normalization.
#   - Normalizes IR discrete energy before convolution, preserving
#     a linear and more consistent wet/dry relationship.
#   - Uses one common IR-energy gain for stereo, preserving L/R balance.
#   - Bounds Gaussian erosion multipliers to [0, 2].
#   - Right logarithmic envelope now reaches zero like the left.
#   - Hann-band filtering is applied to the IR before convolution.
#   - Cutoffs and smoothing adapt safely to Nyquist.
#   - 0% wet uses a true dry-only fast path.
#   - Output duration is source + requested tail; convolution is
#     sampled into a fixed output canvas, trimming/padding as needed.
#   - Visualization updated to the Praat AudioTools house style.
# ============================================================

form Temporal Erosion
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Erosion
        option Medium Erosion
        option Heavy Erosion
        option Extreme Erosion

    comment === IR Parameters ===
    positive Tail_duration_s 3.0
    positive Impulse_duration_s 5.0
    positive Poisson_density 2500

    comment === Filtering ===
    positive Low_cutoff_Hz 100
    positive High_cutoff_Hz 8000
    positive Smoothing_Hz 100

    comment === Erosion ===
    real Erosion_randomness 0.3
    comment (Gaussian roughness standard deviation; 0 = no roughening)

    comment === Mix ===
    real Wet_dry_percent 50
    comment (0 = dry only, 100 = wet only)

    comment === Output ===
    positive Fadeout_duration_s 1.2
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

if numChannels <> 1 and numChannels <> 2
    exitScript: "Temporal Erosion currently supports mono or stereo Sound objects only."
endif

if sr < 1000
    exitScript: "Sampling frequency is too low for Temporal Erosion."
endif

# === Apply Presets ===
if preset = 2
    tail_duration_s = 2.0
    impulse_duration_s = 3.0
    poisson_density = 1500
    low_cutoff_Hz = 120
    high_cutoff_Hz = 7000
    smoothing_Hz = 80
    erosion_randomness = 0.2
    fadeout_duration_s = 1.0
    wet_dry_percent = 35
    presetName$ = "Subtle"
elsif preset = 3
    tail_duration_s = 3.0
    impulse_duration_s = 5.0
    poisson_density = 2500
    low_cutoff_Hz = 100
    high_cutoff_Hz = 8000
    smoothing_Hz = 100
    erosion_randomness = 0.3
    fadeout_duration_s = 1.2
    wet_dry_percent = 50
    presetName$ = "Medium"
elsif preset = 4
    tail_duration_s = 4.0
    impulse_duration_s = 7.0
    poisson_density = 4000
    low_cutoff_Hz = 80
    high_cutoff_Hz = 9000
    smoothing_Hz = 120
    erosion_randomness = 0.4
    fadeout_duration_s = 1.5
    wet_dry_percent = 65
    presetName$ = "Heavy"
elsif preset = 5
    tail_duration_s = 5.0
    impulse_duration_s = 10.0
    poisson_density = 6000
    low_cutoff_Hz = 60
    high_cutoff_Hz = 10000
    smoothing_Hz = 150
    erosion_randomness = 0.5
    fadeout_duration_s = 2.0
    wet_dry_percent = 80
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Validate / derive parameters ===
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

if erosion_randomness < 0
    erosion_randomness = 0
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level
nyquist = sr / 2
maxFilterHz = 0.95 * nyquist

effectiveLow = low_cutoff_Hz
effectiveHigh = min(high_cutoff_Hz, maxFilterHz)

if effectiveLow >= effectiveHigh
    exitScript: "Low cutoff must be below the effective high cutoff (95% of Nyquist)."
endif

# Keep the Hann transition inside the usable spectrum and prevent
# an excessively wide lower transition from reaching through DC.
effectiveSmoothing = min(smoothing_Hz, effectiveLow, nyquist - effectiveHigh, 0.5 * (effectiveHigh - effectiveLow))
if effectiveSmoothing <= 0
    exitScript: "The effective filter smoothing is zero; please adjust the cutoff frequencies."
endif

# Slightly decorrelated right-channel filter, bounded independently.
rightLow = effectiveLow * 1.2
rightHigh = min(high_cutoff_Hz * 0.94, maxFilterHz)
if rightLow >= rightHigh
    rightLow = effectiveLow
    rightHigh = effectiveHigh
endif

rightSmoothing = min(smoothing_Hz * 0.9, rightLow, nyquist - rightHigh, 0.5 * (rightHigh - rightLow))
if rightSmoothing <= 0
    rightSmoothing = effectiveSmoothing
endif

fadeDuration = min(fadeout_duration_s, tail_duration_s)
fadeStart = originalDur + tail_duration_s - fadeDuration
totalDur = originalDur + tail_duration_s

# The manual documents 2000 samples as a typical interpolation depth.
sincDepth = 2000
adaptationTime = 0.02

# ============================================================
# INFO
# ============================================================

writeInfoLine: "=== Temporal Erosion ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "IR duration: ", fixed$(impulse_duration_s, 2), " s"
appendInfoLine: "Poisson density: ", fixed$(poisson_density, 0), " events/s"
appendInfoLine: "Expected events (L): ", fixed$(impulse_duration_s * poisson_density, 0)
appendInfoLine: "Erosion sigma: ", fixed$(erosion_randomness, 2), " (bounded multiplier 0..2)"
appendInfoLine: "Effective L band: ", fixed$(effectiveLow, 0), " - ", fixed$(effectiveHigh, 0), " Hz"
if numChannels = 2
    appendInfoLine: "Effective R band: ", fixed$(rightLow, 0), " - ", fixed$(rightHigh, 0), " Hz"
endif
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Output tail: ", fixed$(tail_duration_s, 2), " s"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

if wet_level = 0
    # True dry-only fast path: no IR, convolution, filtering, or scaling.
    selectObject: original
    Copy: originalName$ + "_erosion_" + presetName$
    result = selected("Sound")

else
    erosion_str$ = string$(erosion_randomness)
    original_start_str$ = string$(originalStart)
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    fade_start_str$ = string$(fadeStart)
    fade_str$ = string$(fadeDuration)

    if numChannels = 2
        # ====================================================
        # STEREO
        # ====================================================

        selectObject: original
        Extract one channel: 1
        leftChannel = selected("Sound")

        selectObject: original
        Extract one channel: 2
        rightChannel = selected("Sound")

        # ---- Left IR ----
        Create Poisson process: "erosion_poisson_left", 0, impulse_duration_s, poisson_density
        poissonLeft = selected("PointProcess")

        To Sound (pulse train): sr, 1, adaptationTime, sincDepth
        irLeftRaw = selected("Sound")

        # Logarithmic envelope reaches exactly zero at xmax.
        # Gaussian roughening is bounded to preserve amplitude semantics.
        Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * min(2, max(0, randomGauss(1, " + erosion_str$ + ")))"

        Filter (pass Hann band): effectiveLow, effectiveHigh, effectiveSmoothing
        irLeft = selected("Sound")
        removeObject: irLeftRaw

        # ---- Right IR ----
        Create Poisson process: "erosion_poisson_right", 0, impulse_duration_s * 0.96, poisson_density * 0.92
        poissonRight = selected("PointProcess")

        To Sound (pulse train): sr, 1, adaptationTime, sincDepth
        irRightRaw = selected("Sound")

        erosionR = erosion_randomness * 1.17
        erosion_R_str$ = string$(erosionR)
        Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * min(2, max(0, randomGauss(1, " + erosion_R_str$ + ")))"

        Filter (pass Hann band): rightLow, rightHigh, rightSmoothing
        irRight = selected("Sound")
        removeObject: irRightRaw

        # Normalize discrete IR energy with ONE common stereo gain.
        # For "sum" convolution, sum(h^2)=1 gives approximately unity
        # white-noise RMS gain. Praat energy is sum(h^2)/sr.
        selectObject: irLeft
        energyLeft = Get energy: 0, 0

        selectObject: irRight
        energyRight = Get energy: 0, 0

        maxIrEnergy = max(energyLeft, energyRight)
        if maxIrEnergy <= 0
            exitScript: "Generated impulse response has zero energy."
        endif

        irGain = 1 / sqrt(maxIrEnergy * sr)
        ir_gain_str$ = string$(irGain)

        selectObject: irLeft
        Formula: "self * " + ir_gain_str$

        selectObject: irRight
        Formula: "self * " + ir_gain_str$

        # Convolution.
        appendInfoLine: "  Convolving left..."
        selectObject: leftChannel, irLeft
        Convolve: "sum", "zero"
        convLeft = selected("Sound")

        appendInfoLine: "  Convolving right..."
        selectObject: rightChannel, irRight
        Convolve: "sum", "zero"
        convRight = selected("Sound")

        # Fixed wet canvases: map convolution start to output time zero;
        # object() supplies zero outside the convolution's time domain.
        selectObject: convLeft
        convLeftStart = Get start time
        conv_left_id_str$ = string$(convLeft)
        conv_left_start_str$ = string$(convLeftStart)

        Create Sound from formula: "erosion_wet_left", 1, 0, totalDur, sr, "object(" + conv_left_id_str$ + ", x + " + conv_left_start_str$ + ", 1)"
        wetLeft = selected("Sound")

        selectObject: convRight
        convRightStart = Get start time
        conv_right_id_str$ = string$(convRight)
        conv_right_start_str$ = string$(convRightStart)

        Create Sound from formula: "erosion_wet_right", 1, 0, totalDur, sr, "object(" + conv_right_id_str$ + ", x + " + conv_right_start_str$ + ", 1)"
        wetRight = selected("Sound")

        # Fade WET only, and only inside the requested tail.
        selectObject: wetLeft
        Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_str$ + ")) else self fi"

        selectObject: wetRight
        Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_str$ + ")) else self fi"

        # True wet/dry mix, preserving the original stereo dry path.
        original_id_str$ = string$(original)

        selectObject: wetLeft
        Formula: "self * " + wet_str$ + " + object(" + original_id_str$ + ", x + " + original_start_str$ + ", 1) * " + dry_str$

        selectObject: wetRight
        Formula: "self * " + wet_str$ + " + object(" + original_id_str$ + ", x + " + original_start_str$ + ", 2) * " + dry_str$

        selectObject: wetLeft, wetRight
        Combine to stereo
        result = selected("Sound")
        Rename: originalName$ + "_erosion_" + presetName$

        # One common down-only safety gain after stereo combination.
        selectObject: result
        resultPeak = Get absolute extremum: 0, 0, "none"
        if resultPeak > 0.98
            Scale peak: 0.98
        endif

        removeObject: leftChannel, rightChannel
        removeObject: poissonLeft, poissonRight, irLeft, irRight
        removeObject: convLeft, convRight, wetLeft, wetRight

    else
        # ====================================================
        # MONO
        # ====================================================

        Create Poisson process: "erosion_poisson_mono", 0, impulse_duration_s, poisson_density
        poissonMono = selected("PointProcess")

        To Sound (pulse train): sr, 1, adaptationTime, sincDepth
        irMonoRaw = selected("Sound")

        Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * min(2, max(0, randomGauss(1, " + erosion_str$ + ")))"

        Filter (pass Hann band): effectiveLow, effectiveHigh, effectiveSmoothing
        irMono = selected("Sound")
        removeObject: irMonoRaw

        # Normalize discrete IR energy before convolution.
        selectObject: irMono
        irEnergy = Get energy: 0, 0
        if irEnergy <= 0
            exitScript: "Generated impulse response has zero energy."
        endif

        irGain = 1 / sqrt(irEnergy * sr)
        ir_gain_str$ = string$(irGain)
        Formula: "self * " + ir_gain_str$

        appendInfoLine: "  Convolving mono..."
        selectObject: original, irMono
        Convolve: "sum", "zero"
        convMono = selected("Sound")

        selectObject: convMono
        convMonoStart = Get start time
        conv_mono_id_str$ = string$(convMono)
        conv_mono_start_str$ = string$(convMonoStart)

        Create Sound from formula: "erosion_wet_mono", 1, 0, totalDur, sr, "object(" + conv_mono_id_str$ + ", x + " + conv_mono_start_str$ + ", 1)"
        wetMono = selected("Sound")

        # Fade WET only.
        selectObject: wetMono
        Formula: "if x > " + fade_start_str$ + " then self * (0.5 + 0.5*cos(pi*(x-" + fade_start_str$ + ")/" + fade_str$ + ")) else self fi"

        # True wet/dry mix.
        original_id_str$ = string$(original)
        Formula: "self * " + wet_str$ + " + object(" + original_id_str$ + ", x + " + original_start_str$ + ", 1) * " + dry_str$

        Rename: originalName$ + "_erosion_" + presetName$
        result = wetMono

        selectObject: result
        resultPeak = Get absolute extremum: 0, 0, "none"
        if resultPeak > 0.98
            Scale peak: 0.98
        endif

        removeObject: poissonMono, irMono, convMono
    endif
endif

selectObject: result
resultDur = Get total duration

# ============================================================
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7


    # Main title.
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "Temporal Erosion | " + presetName$ + " | v0.4.1"

    # Metadata.
    Select outer viewport: 0, 8, 0.36, 0.58
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | Poisson IR " + fixed$(poisson_density, 0) + "/s | Wet " + fixed$(wet_dry_percent, 0) + "%"

    # Dry waveform.
    Select outer viewport: 0, 8, 0.65, 1.35
    Select inner viewport: 0.60, 7.70, 0.72, 1.28
    selectObject: original
    Colour: "{0.65, 0.65, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.72, 1.28
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.72, 1.28
    Axes: 0, 1, 0, 1

    # Output waveform including the complete tail.
    Select outer viewport: 0, 8, 1.42, 2.12
    Select inner viewport: 0.60, 7.70, 1.49, 2.05
    selectObject: result
    Colour: "{0.68, 0.48, 0.48}"
    Draw: 0, resultDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 1.49, 2.05
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Output"
    Select inner viewport: 0.60, 7.70, 1.49, 2.05
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # ---- Left analysis panel: logarithmic decay ----
    Select outer viewport: 0.15, 3.95, 2.35, 3.88
    Select inner viewport: 0.60, 3.85, 2.62, 3.68
    Axes: 0, 1, 0, 1.12
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1.12

    Colour: "{0.72, 0.42, 0.42}"
    Line width: 2
    prevX = 0
    prevY = 1
    for i from 1 to 80
        t = i / 80
        env = 1 - log10(1 + 9 * t)
        Draw line: prevX, prevY, t, env
        prevX = t
        prevY = env
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.62, 3.68
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amplitude"
    Select inner viewport: 0.60, 3.85, 2.62, 3.68
    Axes: 0, 1, 0, 1.12
    Text bottom: "yes", "Normalized IR time"

    Select outer viewport: 0.15, 3.95, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Logarithmic decay envelope"

    # ---- Right analysis panel: effective Hann bands ----
    Select outer viewport: 4.05, 7.85, 2.35, 3.88
    Select inner viewport: 4.45, 7.70, 2.62, 3.68
    Axes: 0, nyquist / 1000, 0, 1.12
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, nyquist / 1000, 0, 1.12

    lowK = effectiveLow / 1000
    highK = effectiveHigh / 1000
    smoothK = effectiveSmoothing / 1000

    Colour: "{0.45, 0.65, 0.55}"
    Line width: 2
    Draw line: 0, 0, lowK - smoothK, 0
    Draw line: lowK - smoothK, 0, lowK, 1
    Draw line: lowK, 1, highK, 1
    Draw line: highK, 1, highK + smoothK, 0
    Draw line: highK + smoothK, 0, nyquist / 1000, 0

    if numChannels = 2
        rightLowK = rightLow / 1000
        rightHighK = rightHigh / 1000
        rightSmoothK = rightSmoothing / 1000

        Colour: "{0.50, 0.55, 0.72}"
        Dashed line
        Draw line: 0, 0, rightLowK - rightSmoothK, 0
        Draw line: rightLowK - rightSmoothK, 0, rightLowK, 1
        Draw line: rightLowK, 1, rightHighK, 1
        Draw line: rightHighK, 1, rightHighK + rightSmoothK, 0
        Draw line: rightHighK + rightSmoothK, 0, nyquist / 1000, 0
        Solid line
    endif

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 2.62, 3.68
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Gain"
    Select inner viewport: 4.45, 7.70, 2.62, 3.68
    Axes: 0, nyquist / 1000, 0, 1.12
    Text bottom: "yes", "Frequency (kHz)"

    Select outer viewport: 4.05, 7.85, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "IR spectral window"

    # Summary panel.
    Select outer viewport: 0, 8, 3.98, 4.98
    Select inner viewport: 0.60, 7.70, 4.05, 4.91
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.35}"
    Font size: 6
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "IR " + fixed$(impulse_duration_s, 1) + " s | Tail " + fixed$(tail_duration_s, 1) + " s | Density " + fixed$(poisson_density, 0) + "/s | Erosion sigma " + fixed$(erosion_randomness, 2)
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Band " + fixed$(effectiveLow, 0) + "-" + fixed$(effectiveHigh, 0) + " Hz | Fade " + fixed$(fadeDuration, 1) + " s | Output " + fixed$(resultDur, 2) + " s"

    Select inner viewport: 0.60, 7.70, 4.05, 4.91
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 5.08
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# FINAL INFO / PLAY
# ============================================================

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output duration: ", fixed$(resultDur, 3), " s"

if play_result
    selectObject: result
    Play
endif

selectObject: result
