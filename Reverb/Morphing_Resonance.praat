# ============================================================
# Praat AudioTools - Morphing_Resonance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Morphing Resonance - creates reverb with frequency-sweeping
#   (chirp) modulation. The impulse response has a frequency
#   that increases over time, creating shimmering, evolving
#   reverb tails. Includes chorus layer for added thickness.
#   Stereo processing uses decorrelated parameters.
#
# ALGORITHM NOTE on the chirp math:
#   The IR's modulation term is sin(2*pi*x*(fstart + frange*t/T)),
#   where t = x - xmin and T = xmax - xmin. The phase argument
#   expands to 2*pi*(fstart*t + frange*t^2/T), whose derivative
#   (instantaneous frequency) is fstart + 2*frange*t/T. So the
#   ACTUAL chirp sweeps from fstart at t=0 to fstart+2*frange at
#   t=T — i.e. the labelled Frequency_range_Hz parameter
#   contributes 2x its value to the sweep range. This has been
#   true since v0.1 and the presets are tuned to it. v0.3 keeps
#   the audio behaviour unchanged and updates the visualization
#   to draw the actual sweep range (fstart -> fstart+2*frange)
#   rather than the labelled value. A future v0.4 could fix the
#   math by using sin(2*pi*(fstart*x + frange*(x-xmin)^2/(2*T)))
#   for a proper continuous-phase chirp, but that would change
#   the audio character and require re-tuning the four presets.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Public form/defaults, preset values, output naming, and final selection
#     are unchanged.
#   - Corrected Wet/Dry semantics. The internal result buffer contains dry +
#     effect; the final mix now explicitly extracts (result - dry), so 0% wet
#     = dry only and 100% wet = chirp/chorus effect only.
#   - Silent-tail channel count now exactly matches the source, fixing 3+
#     channel Concatenate failures. Mono IR convolution is shared across all
#     channels for non-stereo multichannel input.
#   - Object reads in multichannel formulas use explicit row/col routing.
#   - Fadeout duration is limited to the appended tail, so the fade cannot
#     begin before the end of the source material.
#   - Chorus delays are clamped to at least one sample, avoiding zero-delay
#     recursive same-sample gain for tiny Custom values.
#   - Exponential_base is internally clamped to >= 1 so Custom values below 1
#     cannot turn the intended decay envelope into exponential growth.
#   - Stereo normalization now happens after L/R recombination, preserving the
#     decorrelated channel balance. Scale_peak remains target normalization but
#     is silence-safe.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. Same Poisson + pulse-train
#     IR generation, same chirp-modulated decay envelope, same
#     convolution, same recursive-in-place chorus structure
#     with 0.7 attenuation, same dry/wet mix, same cosine
#     fadeout, same Scale peak. Same 4 presets with same values.
#     Same stereo decorrelation (densityR = density * 0.97,
#     baseR = base * 0.94, etc.).
#   - Form syntax modernized: `optionmenu Preset:` with colon.
#   - Dropped 8 decorative `comment` lines (3 section dividers,
#     1 instructional, 4 inline parentheticals) to keep the form
#     compact. Lesson from the rest of the suite — decorative
#     comments cost vertical screen real estate without
#     functional value.
#   - Visualization rewritten to suite 8x8 standard (v0.2 was
#     8x4.1):
#       Title bar + metadata subtitle (preset, chirp range,
#         modulation depth, chorus, wet/dry, fadeout)
#       Panel A (left, headline): chirp instantaneous frequency
#         diagram — REPLACES v0.2's diagram that drew the
#         labelled range (fstart -> fstart+frange). v0.3 draws
#         the ACTUAL sweep (fstart -> fstart+2*frange) so the
#         visualization matches what the audio produces. Title
#         line clarifies this.
#       Panel B (right, headline): IR waveform (first 2 s) —
#         shows the actual impulse response character, including
#         the modulation-depth decay envelope visually
#       Panel C: zoom overlay (first 200 ms, gray = original,
#         purple = result)
#       Panel D: result waveform (full file)
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Fixed selection and formula syntax
#   - Fixed chorus delay formula
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Morphing Resonance v0.5.1
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Morphing
        option Medium Morphing
        option Heavy Morphing
        option Extreme Morphing
    positive Tail_duration_s 2.0
    positive Poisson_density 1800
    positive Exponential_base 85
    positive Frequency_start_Hz 220
    positive Frequency_range_Hz 880
    positive Modulation_depth 0.5
    positive Chorus_mix 0.3
    positive Chorus_delay_ms 10
    positive Convolution_mix 0.32
    real Wet_dry_percent 60
    positive Fadeout_duration_s 1.0
    positive Scale_peak 0.9
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Morphing
    tail_duration_s = 1.5
    poisson_density = 1200
    exponential_base = 95
    frequency_start_Hz = 180
    frequency_range_Hz = 600
    modulation_depth = 0.35
    convolution_mix = 0.22
    chorus_mix = 0.2
    chorus_delay_ms = 8
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Morphing
    tail_duration_s = 2.0
    poisson_density = 1800
    exponential_base = 85
    frequency_start_Hz = 220
    frequency_range_Hz = 880
    modulation_depth = 0.5
    convolution_mix = 0.32
    chorus_mix = 0.3
    chorus_delay_ms = 10
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Morphing
    tail_duration_s = 2.5
    poisson_density = 2400
    exponential_base = 75
    frequency_start_Hz = 260
    frequency_range_Hz = 1150
    modulation_depth = 0.65
    convolution_mix = 0.42
    chorus_mix = 0.4
    chorus_delay_ms = 12
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Morphing
    tail_duration_s = 3.5
    poisson_density = 3200
    exponential_base = 65
    frequency_start_Hz = 300
    frequency_range_Hz = 1500
    modulation_depth = 0.8
    convolution_mix = 0.52
    chorus_mix = 0.5
    chorus_delay_ms = 15
    fadeout_duration_s = 1.8
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Internal safety guards; built-in presets are unchanged.
if tail_duration_s < 1 / sr
    tail_duration_s = 1 / sr
endif
if exponential_base < 1
    exponential_base = 1
endif
if chorus_delay_ms < 1000 / sr
    chorus_delay_ms = 1000 / sr
endif
if fadeout_duration_s > tail_duration_s
    effectiveFadeout = tail_duration_s
else
    effectiveFadeout = fadeout_duration_s
endif
if effectiveFadeout < 1 / sr
    effectiveFadeout = 1 / sr
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Convert chorus delay to seconds
chorus_delay_s = chorus_delay_ms / 1000

# IR duration
irDuration = 4.5

# === Info ===
writeInfoLine: "=== Morphing Resonance v0.4 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Poisson density: ", poisson_density, " impulses/s"
appendInfoLine: "Exponential base: ", exponential_base
appendInfoLine: "Chirp labelled: ", frequency_start_Hz, " -> ", frequency_start_Hz + frequency_range_Hz, " Hz"
appendInfoLine: "Chirp actual:   ", frequency_start_Hz, " -> ", frequency_start_Hz + 2 * frequency_range_Hz, " Hz"
appendInfoLine: "Modulation depth: ", modulation_depth
appendInfoLine: "Chorus: ", chorus_mix, " @ ", chorus_delay_ms, " ms"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: "Fadeout: ", effectiveFadeout, " s (requested ", fadeout_duration_s, " s)"
appendInfoLine: ""

# ============================================================
# PROCESSING (unchanged from v0.2)
# ============================================================

appendInfoLine: "Processing..."

# Create silent tail with the exact source channel count.
Create Sound from formula: "silent_tail", numChannels, 0, tail_duration_s, sr, "0"
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

totalDur = originalDur + tail_duration_s

# Build formula strings
base_str$ = string$(exponential_base)
depth_str$ = string$(modulation_depth)
fstart_str$ = string$(frequency_start_Hz)
frange_str$ = string$(frequency_range_Hz)
mix_str$ = string$(convolution_mix)
chorus_str$ = string$(chorus_mix)

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # === LEFT CHANNEL ===
    appendInfoLine: "  Creating left IR..."
    
    selectObject: leftChannel
    Copy: "sound_left"
    aLeft = selected("Sound")
    
    Create Poisson process: "poisson_L", 0, irDuration, poisson_density
    poissonL = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, 0.055, 2200
    irLeftRaw = selected("Sound")
    
    # Apply chirp modulation envelope
    Formula: "self * " + base_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + depth_str$ + "*sin(2*pi*x*(" + fstart_str$ + " + " + frange_str$ + "*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
    irLeft = irLeftRaw
    
    # Convolve
    selectObject: aLeft, irLeft
    Convolve: "sum", "zero"
    bLeft = selected("Sound")
    Formula: "self * " + mix_str$
    
    # Add chorus (delayed copy)
    selectObject: bLeft
    Copy: "chorus_left"
    chorusLeft = selected("Sound")
    
    delay_samp = max(1, round(chorus_delay_s * sr))
    delay_str$ = string$(delay_samp)
    
    Formula: "if col > " + delay_str$ + " then 0.7 * (self + " + chorus_str$ + " * self[col - " + delay_str$ + "]) else self * 0.7 fi"
    
    # Combine: dry + chorus
    aLeft_str$ = string$(aLeft)
    chorusLeft_str$ = string$(chorusLeft)
    
    selectObject: aLeft
    Copy: "result_left"
    resultLeft = selected("Sound")
    Formula: "self + object[" + chorusLeft_str$ + ", row, col]"
    
    # === RIGHT CHANNEL (decorrelated) ===
    appendInfoLine: "  Creating right IR..."
    
    selectObject: rightChannel
    Copy: "sound_right"
    aRight = selected("Sound")
    
    # Slightly different parameters
    densityR = poisson_density * 0.97
    Create Poisson process: "poisson_R", 0, irDuration * 0.96, densityR
    poissonR = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, 0.05, 2100
    irRightRaw = selected("Sound")
    
    # Different chirp parameters
    baseR_str$ = string$(exponential_base * 0.94)
    depthR_str$ = string$(modulation_depth * 0.9)
    fstartR_str$ = string$(frequency_start_Hz * 1.09)
    frangeR_str$ = string$(frequency_range_Hz * 0.91)
    
    Formula: "self * " + baseR_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + depthR_str$ + "*sin(2*pi*x*(" + fstartR_str$ + " + " + frangeR_str$ + "*(x-xmin)/(xmax-xmin))) * exp(-2.8*(x-xmin)/(xmax-xmin)))"
    irRight = irRightRaw
    
    # Convolve
    selectObject: aRight, irRight
    Convolve: "sum", "zero"
    bRight = selected("Sound")
    mixR_str$ = string$(convolution_mix * 0.94)
    Formula: "self * " + mixR_str$
    
    # Add chorus
    selectObject: bRight
    Copy: "chorus_right"
    chorusRight = selected("Sound")
    
    delayR_samp = max(1, round(chorus_delay_s * 0.8 * sr))
    delayR_str$ = string$(delayR_samp)
    chorusR_str$ = string$(chorus_mix * 0.83)
    
    Formula: "if col > " + delayR_str$ + " then 0.7 * (self + " + chorusR_str$ + " * self[col - " + delayR_str$ + "]) else self * 0.7 fi"
    
    # Combine
    chorusRight_str$ = string$(chorusRight)
    
    selectObject: aRight
    Copy: "result_right"
    resultRight = selected("Sound")
    Formula: "self + object[" + chorusRight_str$ + ", row, col]"
    
    # === APPLY TRUE WET/DRY ===
    # resultLeft/resultRight currently contain dry + effect.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_str$ = string$(leftChannel)
    right_str$ = string$(rightChannel)

    selectObject: resultLeft
    Formula: "object[" + left_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + left_str$ + ", row, col]) * " + wet_str$

    selectObject: resultRight
    Formula: "object[" + right_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + right_str$ + ", row, col]) * " + wet_str$

    # Apply fadeout only inside the appended tail.
    fade_start = totalDur - effectiveFadeout
    fade_str$ = string$(effectiveFadeout)
    start_str$ = string$(fade_start)
    
    selectObject: resultLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"

    selectObject: resultRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"

    # Combine first, then normalize once to preserve L/R balance.
    selectObject: resultLeft, resultRight
    Combine to stereo
    result = selected("Sound")
    resultPeakBeforeScale = Get absolute extremum: 0, 0, "None"
    if resultPeakBeforeScale > 0
        Scale peak: scale_peak
    endif
    Rename: originalName$ + "_morphing_" + presetName$
    
    # Store IR for visualization
    irForViz = irLeft
    
    # Cleanup (keep irForViz until viz is done)
    removeObject: poissonL, poissonR
    removeObject: irRight
    removeObject: leftChannel, rightChannel
    removeObject: aLeft, aRight
    removeObject: bLeft, bRight
    removeObject: chorusLeft, chorusRight
    removeObject: resultLeft, resultRight
    removeObject: extendedSound

else
    # === MONO / SHARED MULTICHANNEL PROCESSING ===
    appendInfoLine: "  Processing mono/shared multichannel..."
    
    selectObject: extendedSound
    Copy: "sound_mono"
    aMono = selected("Sound")
    
    Create Poisson process: "poisson_mono", 0, irDuration, poisson_density
    poissonMono = selected("PointProcess")
    
    To Sound (pulse train): sr, 1, 0.055, 2200
    irMono = selected("Sound")
    
    Formula: "self * " + base_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + " + depth_str$ + "*sin(2*pi*x*(" + fstart_str$ + " + " + frange_str$ + "*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
    
    # Convolve
    selectObject: aMono, irMono
    Convolve: "sum", "zero"
    bMono = selected("Sound")
    Formula: "self * " + mix_str$
    
    # Add chorus
    selectObject: bMono
    Copy: "chorus_mono"
    chorusMono = selected("Sound")
    
    delay_samp = max(1, round(chorus_delay_s * sr))
    delay_str$ = string$(delay_samp)
    
    Formula: "if col > " + delay_str$ + " then 0.7 * (self + " + chorus_str$ + " * self[col - " + delay_str$ + "]) else self * 0.7 fi"
    
    # Combine
    chorusMono_str$ = string$(chorusMono)
    
    selectObject: aMono
    Copy: "result_mono"
    resultMono = selected("Sound")
    Formula: "self + object[" + chorusMono_str$ + ", row, col]"
    
    # Apply true dry/effect crossfade. resultMono currently contains dry + effect.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    ext_str$ = string$(extendedSound)

    selectObject: resultMono
    Formula: "object[" + ext_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + ext_str$ + ", row, col]) * " + wet_str$

    # Apply fadeout only inside the appended tail.
    fade_start = totalDur - effectiveFadeout
    fade_str$ = string$(effectiveFadeout)
    start_str$ = string$(fade_start)
    
    selectObject: resultMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    resultPeakBeforeScale = Get absolute extremum: 0, 0, "None"
    if resultPeakBeforeScale > 0
        Scale peak: scale_peak
    endif
    Rename: originalName$ + "_morphing_" + presetName$
    result = resultMono
    
    # Store IR for visualization
    irForViz = irMono
    
    # Cleanup (keep irForViz until viz is done)
    removeObject: poissonMono, aMono, bMono, chorusMono, extendedSound
endif

# Capture stats for visualization
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Actual chirp end frequency (sweeps from fstart to fstart + 2*frange, not fstart + frange)
fEndActual = frequency_start_Hz + 2 * frequency_range_Hz

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Black
    Plain line
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##MORPHING RESONANCE##" + " | v0.5.1"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  chirp " + fixed$(frequency_start_Hz, 0) + "-" + fixed$(fEndActual, 0) + " Hz (actual)"
        ... + "  |  mod " + fixed$(modulation_depth, 2)
        ... + "  |  chorus " + fixed$(chorus_mix, 2) + " @ " + fixed$(chorus_delay_ms, 0) + " ms"
        ... + "  |  " + fixed$(wet_dry_percent, 0) + "% wet"
        ... + "  |  fadeout " + fixed$(effectiveFadeout, 2) + " s"

    # ----------------------------------------------------------
    # PANEL A: CHIRP INSTANTANEOUS FREQUENCY  (left, headline)
    # Shows the ACTUAL sweep (fstart -> fstart + 2*frange).
    # Modulation-depth decay envelope drawn separately as a
    # secondary curve.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    Axes: 0, irDuration, 0, fEndActual * 1.1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, irDuration, 0, fEndActual * 1.1
    
    # Reference grid (light dotted lines at 25/50/75% of fEnd)
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, fEndActual * 0.25, irDuration, fEndActual * 0.25
    Draw line: 0, fEndActual * 0.50, irDuration, fEndActual * 0.50
    Draw line: 0, fEndActual * 0.75, irDuration, fEndActual * 0.75
    Solid line
    
    # Inst-freq curve: linear from (0, fstart) to (irDuration, fEndActual)
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 2.5
    nPoints = 100
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * irDuration
        t2 = (p - 1) / nPoints * irDuration
        # ACTUAL chirp: fstart + 2 * frange * (t/T)
        f1 = frequency_start_Hz + 2 * frequency_range_Hz * (t1 / irDuration)
        f2 = frequency_start_Hz + 2 * frequency_range_Hz * (t2 / irDuration)
        Draw line: t1, f1, t2, f2
    endfor
    Line width: 1
    
    # Modulation-depth decay envelope drawn as a secondary
    # curve (normalised to the chirp axis for shared display).
    # Depth(t) = modulation_depth * exp(-3 * t/T). Map to
    # ~fEndActual * 0.3 so it's visible alongside the chirp.
    Colour: "{0.85, 0.50, 0.20}"
    Line width: 1.5
    Dotted line
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * irDuration
        t2 = (p - 1) / nPoints * irDuration
        d1 = modulation_depth * exp(-3 * t1 / irDuration) * fEndActual * 0.30
        d2 = modulation_depth * exp(-3 * t2 / irDuration) * fEndActual * 0.30
        Draw line: t1, d1, t2, d2
    endfor
    Solid line
    
    # Endpoint labels
    Font size: 6
    Colour: "{0.55, 0.35, 0.78}"
    Text: 0, "left", frequency_start_Hz + fEndActual * 0.04, "half",
        ... "  start " + fixed$(frequency_start_Hz, 0) + " Hz"
    Text: irDuration, "right", fEndActual + fEndActual * 0.04, "half",
        ... "end " + fixed$(fEndActual, 0) + " Hz  "
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.95, 4.40
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Inst. freq (Hz)"
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    Axes: 0, irDuration, 0, fEndActual * 1.1
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: IMPULSE RESPONSE WAVEFORM  (right, headline)
    # First 2 s of the actual IR — visually shows the chirp
    # and amplitude-decay behaviour the formula produces.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    irDispDur = min(2, irDuration)
    
    selectObject: irForViz
    ir_peak = Get absolute extremum: 0, irDispDur, "None"
    if ir_peak < 0.001
        ir_peak = 0.001
    endif
    ir_amp = ir_peak * 1.15
    
    Axes: 0, irDispDur, -ir_amp, ir_amp
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, irDispDur, -ir_amp, ir_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, irDispDur, 0
    
    selectObject: irForViz
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 1
    Draw: 0, irDispDur, -ir_amp, ir_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 0.95, 4.40
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "IR amp"
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    Axes: 0, irDispDur, -ir_amp, ir_amp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0.60, 7.70, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Chirp inst. freq (purple) + mod depth decay (orange, normalized)"
    Text: 6.10, "centre", 7.30, "half",
        ... "Impulse response (first " + fixed$(irDispDur, 1) + " s of " + fixed$(irDuration, 1) + " s)"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 200 ms)
    # Gray = original, purple = result.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    zoomDur = 0.2
    if zoomDur > originalDur
        zoomDur = originalDur
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    # Extract mono copies of original and result for zoom display
    selectObject: original
    if numChannels > 1
        Convert to mono
        zoomOrig = selected("Sound")
    else
        Copy: "zoom_orig"
        zoomOrig = selected("Sound")
    endif
    
    selectObject: result
    if numChannels > 1
        Convert to mono
        zoomRes = selected("Sound")
    else
        Copy: "zoom_res"
        zoomRes = selected("Sound")
    endif
    
    selectObject: zoomOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: zoomRes
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original behind
    selectObject: zoomOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Result on top
    selectObject: zoomRes
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    removeObject: zoomOrig, zoomRes
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, purple = result)"
    Select inner viewport: 0.20, 0.48, 4.75, 5.48
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amp"
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    Axes: 0, zoomDur, -z_amp, z_amp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: RESULT WAVEFORM (FULL FILE)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    selectObject: result
    if numChannels > 1
        Convert to mono
        fullRes = selected("Sound")
    else
        Copy: "full_res"
        fullRes = selected("Sound")
    endif
    
    selectObject: fullRes
    out_peak_v = Get absolute extremum: 0, 0, "None"
    if out_peak_v < 0.001
        out_peak_v = 0.001
    endif
    out_amp = out_peak_v * 1.15
    
    Axes: 0, finalDur, -out_amp, out_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -out_amp, out_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # Mark the fadeout start position
    fade_start_pos = totalDur - effectiveFadeout
    if fade_start_pos < finalDur
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: fade_start_pos, -out_amp, fade_start_pos, out_amp
        Solid line
        Font size: 6
        Text: fade_start_pos, "left", out_amp * 0.85, "half", "  fadeout"
    endif
    
    selectObject: fullRes
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1
    Draw: 0, finalDur, -out_amp, out_amp, "no", "Curve"
    
    removeObject: fullRes
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Result (full file)  — true dry/effect mix of chirp-modulated reverb + chorus"
    Select inner viewport: 0.20, 0.48, 5.69, 6.48
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amp"
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    Axes: 0, finalDur, -out_amp, out_amp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.70, 7.70
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", 
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Chirp: " + fixed$(frequency_start_Hz, 0) + "-" + fixed$(fEndActual, 0) + " Hz"
        ... + "  |  Mod depth: " + fixed$(modulation_depth, 2)
        ... + "  |  Poisson density: " + fixed$(poisson_density, 0) + "/s"
        ... + "  |  Exp base: " + fixed$(exponential_base, 0)
    
    Font size: 6
    Text: 0.02, "left", 0.24, "half", 
        ... "Conv mix: " + fixed$(convolution_mix, 2)
        ... + "  |  Chorus: " + fixed$(chorus_mix, 2) + " @ " + fixed$(chorus_delay_ms, 0) + " ms"
        ... + "  |  Wet: " + fixed$(wet_dry_percent, 0) + "\%  "
        ... + "  |  Fade: " + fixed$(effectiveFadeout, 2) + " s"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  " + string$(numChannels) + " ch"
    
    Colour: "Black"
    
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup IR
    removeObject: irForViz

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 7.80
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# If no visualization, still cleanup IR
if draw_visualization = 0
    removeObject: irForViz
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
