# ============================================================
# Praat AudioTools - Magnetic_Tape_Degradation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Magnetic Tape Degradation - a tape-like degradation processor with
#   generation-by-generation memory smoothing, print-through ghosts,
#   progressive high-frequency loss, and transport wow/flutter.
#
#   This is a compositional tape-degradation model rather than a calibrated
#   physical tape-machine emulator. v0.3 keeps every stage stable and gives
#   each control a direct, duration-independent meaning.
#
# Changelog v0.4 (visualization only; DSP unchanged):
#   - Rebuilt the Picture to the AudioTools library standard.
#   - Added a user-facing "Degradation across generations" graph showing the
#     HF-loss stage retention and the actual print-through coefficient per pass.
#   - Memory smear and wow/flutter remain separate explanatory rows because
#     they use different units and should not share a misleading graph axis.
#   - Original/tape waveforms now share one amplitude scale; source names and
#     preset labels are display-safe; full-page export viewport is restored.
#
# Changelog v0.3:
#   - CRITICAL HF-loss fix: v0.2 could amplify DC by almost 2x per generation
#     and its HF factor became negative in strong presets. v0.3 uses a
#     unity-DC, three-tap low-pass blend; repeated generations progressively
#     remove HF without gain explosion or polarity inversion.
#   - TRUE wow/flutter: v0.2's "bias modulation" was amplitude modulation at
#     roughly one cycle per whole file. v0.3 uses time displacement with
#     interpolated reads from a frozen pre-stage Sound, with independent wow
#     and flutter rates/depths.
#   - Print-through delay is now specified in milliseconds and no longer
#     depends on file length, tail length, or sample count.
#   - Print-through reads both pre- and post-ghosts from the same frozen signal,
#     avoiding the left-to-right Formula asymmetry of v0.2.
#   - Memory coefficients are normalized to unity DC gain and remain stable.
#   - Full multichannel preservation: the silent tail uses the source channel
#     count, not a hardcoded mono/stereo branch.
#   - Non-zero Sound time domains are normalized to a zero-based processing
#     copy before concatenation and modulation.
#   - Scale_peak is a safety ceiling only; quiet degraded material is not
#     automatically boosted to the ceiling.
#   - Tail and fadeout may be zero; fadeout is safely bounded by output length.
#   - Visualization spectra use mono analysis copies and stop at Nyquist.
# ============================================================

# --- 1. COMPACT STARTUP FORM ---
form Tape Degradation v0.4
    optionmenu Preset 1
        option Custom
        option Subtle Tape
        option Medium Tape
        option Heavy Tape
        option Extreme Tape

    natural Generations 6
    real Tail_duration_s 2.0

    boolean Draw_visualization 1
    boolean Play_result 1

    boolean Show_advanced_settings 0
endform

# --- 2. DEFAULT PARAMETERS ---
hysteresis_current = 0.70
hysteresis_previous = 0.30
print_through_initial = 0.22
print_through_decay = 0.80
print_through_delay_ms = 120
hf_loss_per_generation = 0.10
wow_rate_Hz = 0.55
wow_depth_ms = 1.20
flutter_rate_Hz = 6.0
flutter_depth_ms = 0.12
scale_peak = 0.87
fadeout_duration_s = 1.0

# --- 3. ADVANCED SETTINGS ---
if show_advanced_settings
    beginPause: "Advanced Tape Degradation"
        comment: "Memory / hysteresis-like smoothing:"
        real: "Hysteresis current", hysteresis_current
        real: "Hysteresis previous", hysteresis_previous

        comment: "Print-through ghosting:"
        real: "Print through initial", print_through_initial
        real: "Print through decay", print_through_decay
        real: "Print through delay ms", print_through_delay_ms

        comment: "Progressive high-frequency loss:"
        real: "HF loss per generation", hf_loss_per_generation

        comment: "Transport instability:"
        real: "Wow rate Hz", wow_rate_Hz
        real: "Wow depth ms", wow_depth_ms
        real: "Flutter rate Hz", flutter_rate_Hz
        real: "Flutter depth ms", flutter_depth_ms

        comment: "Output:"
        real: "Scale peak ceiling", scale_peak
        real: "Fadeout duration s", fadeout_duration_s

    clicked = endPause: "Cancel", "OK", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

# ==============================================================================
# APPLY PRESETS
# ==============================================================================
presetName$ = "Custom"

if preset = 2
    # Subtle Tape
    tail_duration_s = 1.5
    generations = 3
    hysteresis_current = 0.78
    hysteresis_previous = 0.22
    print_through_initial = 0.10
    print_through_decay = 0.85
    print_through_delay_ms = 100
    hf_loss_per_generation = 0.055
    wow_rate_Hz = 0.45
    wow_depth_ms = 0.55
    flutter_rate_Hz = 6.2
    flutter_depth_ms = 0.05
    scale_peak = 0.90
    fadeout_duration_s = 0.8
    presetName$ = "SubtleTape"
elsif preset = 3
    # Medium Tape
    tail_duration_s = 2.0
    generations = 6
    hysteresis_current = 0.70
    hysteresis_previous = 0.30
    print_through_initial = 0.22
    print_through_decay = 0.80
    print_through_delay_ms = 120
    hf_loss_per_generation = 0.10
    wow_rate_Hz = 0.55
    wow_depth_ms = 1.20
    flutter_rate_Hz = 6.0
    flutter_depth_ms = 0.12
    scale_peak = 0.87
    fadeout_duration_s = 1.0
    presetName$ = "MediumTape"
elsif preset = 4
    # Heavy Tape
    tail_duration_s = 2.8
    generations = 10
    hysteresis_current = 0.62
    hysteresis_previous = 0.38
    print_through_initial = 0.32
    print_through_decay = 0.76
    print_through_delay_ms = 160
    hf_loss_per_generation = 0.14
    wow_rate_Hz = 0.65
    wow_depth_ms = 2.1
    flutter_rate_Hz = 5.5
    flutter_depth_ms = 0.20
    scale_peak = 0.85
    fadeout_duration_s = 1.4
    presetName$ = "HeavyTape"
elsif preset = 5
    # Extreme Tape
    tail_duration_s = 4.0
    generations = 15
    hysteresis_current = 0.55
    hysteresis_previous = 0.45
    print_through_initial = 0.42
    print_through_decay = 0.70
    print_through_delay_ms = 220
    hf_loss_per_generation = 0.18
    wow_rate_Hz = 0.72
    wow_depth_ms = 3.8
    flutter_rate_Hz = 5.0
    flutter_depth_ms = 0.35
    scale_peak = 0.82
    fadeout_duration_s = 1.8
    presetName$ = "ExtremeTape"
endif

# ==============================================================================
# VALIDATE + SETUP
# ==============================================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

if generations < 1 or generations > 50
    exitScript: "Generations must be between 1 and 50"
endif
if tail_duration_s < 0
    exitScript: "Tail duration must be >= 0"
endif
if hysteresis_current <= 0 or hysteresis_previous < 0
    exitScript: "Hysteresis current must be > 0 and previous must be >= 0"
endif
if print_through_initial < 0 or print_through_initial > 1
    exitScript: "Print-through initial must be between 0 and 1"
endif
if print_through_decay < 0 or print_through_decay > 1
    exitScript: "Print-through decay must be between 0 and 1"
endif
if print_through_delay_ms <= 0
    exitScript: "Print-through delay must be > 0 ms"
endif
if hf_loss_per_generation < 0 or hf_loss_per_generation >= 1
    exitScript: "HF loss per generation must be >= 0 and < 1"
endif
if wow_rate_Hz < 0 or wow_depth_ms < 0 or flutter_rate_Hz < 0 or flutter_depth_ms < 0
    exitScript: "Wow/flutter rates and depths must be >= 0"
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak ceiling must be > 0 and <= 1"
endif
if fadeout_duration_s < 0
    exitScript: "Fadeout duration must be >= 0"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sourceStart = Get start time
sourceEnd = Get end time
sampling_rate = Get sampling frequency
channels = Get number of channels
originalDuration = Get total duration
nyquist = sampling_rate / 2
spectrumMaxHz = min(8000, nyquist)

# Normalize memory weights to unity DC gain.
memorySum = hysteresis_current + hysteresis_previous
memoryCurrent = hysteresis_current / memorySum
memoryPrevious = hysteresis_previous / memorySum

printDelaySec = print_through_delay_ms / 1000
wowDepthSec = wow_depth_ms / 1000
flutterDepthSec = flutter_depth_ms / 1000

# === Info ===
writeInfoLine: "=== Magnetic Tape Degradation v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s; ", channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Generations: ", generations
appendInfoLine: "Memory weights: ", fixed$(memoryCurrent, 3), " / ", fixed$(memoryPrevious, 3)
appendInfoLine: "Print-through: ", fixed$(print_through_initial, 3), " @ ", fixed$(print_through_delay_ms, 1), " ms; decay ", fixed$(print_through_decay, 3)
appendInfoLine: "HF loss/generation: ", fixed$(hf_loss_per_generation, 3)
appendInfoLine: "Wow: ", fixed$(wow_rate_Hz, 2), " Hz @ ", fixed$(wow_depth_ms, 2), " ms"
appendInfoLine: "Flutter: ", fixed$(flutter_rate_Hz, 2), " Hz @ ", fixed$(flutter_depth_ms, 2), " ms"
appendInfoLine: ""

# ==============================================================================
# ZERO-BASED SOURCE + TAIL
# ==============================================================================
selectObject: original
sourceZero = Copy: "tape_source"
Shift times to: "start time", 0

if tail_duration_s > 0
    Create Sound from formula: "silent_tail", channels, 0, tail_duration_s, sampling_rate, "0"
    silentTail = selected("Sound")
    selectObject: sourceZero, silentTail
    Concatenate
    extended = selected("Sound")
    removeObject: sourceZero, silentTail
else
    selectObject: sourceZero
    extended = Copy: "extended"
    removeObject: sourceZero
endif
Rename: "extended"

selectObject: extended
result = Copy: "tape_work"
totalDuration = Get total duration

# ==============================================================================
# MAIN GENERATION LOOP
# ==============================================================================
appendInfoLine: "Processing generations..."
printThrough = print_through_initial

for gen from 1 to generations
    appendInfoLine: "  Gen ", gen, ": print=", fixed$(printThrough, 3), " HF=", fixed$(hf_loss_per_generation, 3)

    # ------------------------------------------------------------------
    # 1) Hysteresis-like magnetic memory.
    # A normalized one-pole memory stage: stable because memoryPrevious < 1,
    # and DC gain is exactly one after coefficient normalization.
    # ------------------------------------------------------------------
    selectObject: result
    Formula: "if col > 1 then memoryCurrent * self + memoryPrevious * self[row, col - 1] else self fi"

    # ------------------------------------------------------------------
    # 2) Print-through: symmetric pre/post ghosts from one frozen snapshot.
    # Divide by (1 + printThrough) so DC gain remains one.
    # ------------------------------------------------------------------
    if printThrough > 0
        selectObject: result
        printFrozen = Copy: "print_frozen"
        printID$ = string$(printFrozen)
        selectObject: result
        Formula: "(object(" + printID$ + ", x, row) + printThrough * 0.5 * (object(" + printID$ + ", x - printDelaySec, row) + object(" + printID$ + ", x + printDelaySec, row))) / (1 + printThrough)"
        removeObject: printFrozen
    endif

    # ------------------------------------------------------------------
    # 3) Progressive high-frequency loss.
    # Blend with [0.25, 0.5, 0.25] smoothing. Both branches have DC gain 1,
    # so this removes HF without generation-dependent amplitude explosion.
    # ------------------------------------------------------------------
    if hf_loss_per_generation > 0
        selectObject: result
        hfFrozen = Copy: "hf_frozen"
        hfID$ = string$(hfFrozen)
        selectObject: result
        Formula: "(1 - hf_loss_per_generation) * object[" + hfID$ + ", row, col] + hf_loss_per_generation * (0.25 * object[" + hfID$ + ", row, col - 1] + 0.5 * object[" + hfID$ + ", row, col] + 0.25 * object[" + hfID$ + ", row, col + 1])"
        removeObject: hfFrozen
    endif

    # ------------------------------------------------------------------
    # 4) Wow/flutter: time displacement, not amplitude modulation.
    # Each generation receives independent phases, like a new transport pass.
    # Positional object() reads are linearly interpolated by Praat.
    # ------------------------------------------------------------------
    if (wow_rate_Hz > 0 and wow_depth_ms > 0) or (flutter_rate_Hz > 0 and flutter_depth_ms > 0)
        wowPhase = randomUniform(0, 2 * pi)
        flutterPhase = randomUniform(0, 2 * pi)
        selectObject: result
        speedFrozen = Copy: "speed_frozen"
        speedID$ = string$(speedFrozen)
        selectObject: result
        Formula: "object(" + speedID$ + ", min(totalDuration, max(0, x + wowDepthSec * sin(2*pi*wow_rate_Hz*x + wowPhase) + flutterDepthSec * sin(2*pi*flutter_rate_Hz*x + flutterPhase))), row)"
        removeObject: speedFrozen
    endif

    printThrough = printThrough * print_through_decay
endfor

# ==============================================================================
# OUTPUT SAFETY + FADE
# ==============================================================================
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > scale_peak
    Formula: "self * scale_peak / resultPeak"
endif

if fadeout_duration_s > 0
    effectiveFade = min(fadeout_duration_s, totalDuration)
    if effectiveFade > 0
        fadeStart = totalDuration - effectiveFade
        Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / effectiveFade)) else self fi"
    endif
endif

Rename: original_name$ + "_tape_" + presetName$
resultName$ = selected$("Sound")

removeObject: extended

# ==============================================================================
# VISUALIZATION
# ==============================================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 6.80

    vizOriginalName$ = replace$(original_name$, "_", "\_ ", 0)
    presetDisplay$ = "Custom"
    if preset = 2
        presetDisplay$ = "Subtle Tape"
    elsif preset = 3
        presetDisplay$ = "Medium Tape"
    elsif preset = 4
        presetDisplay$ = "Heavy Tape"
    elsif preset = 5
        presetDisplay$ = "Extreme Tape"
    endif

    # Visualization copies: zero-based mono views for honest time/amplitude comparison.
    selectObject: original
    if channels > 1
        vizOriginal = Convert to mono
    else
        vizOriginal = Copy: "viz_original"
    endif
    selectObject: vizOriginal
    Shift times to: "start time", 0

    selectObject: result
    if channels > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz_result"
    endif
    selectObject: vizResult
    Shift times to: "start time", 0

    selectObject: vizOriginal
    vizOrigPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    vizResultPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(vizOrigPeak, vizResultPeak)
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.12

    # Title block: library standard.
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Magnetic Tape Degradation v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizOriginalName$ + " | " + presetDisplay$
        ... + " | " + string$(generations) + " generations"
        ... + " | " + string$(channels) + " ch"
        ... + " | " + fixed$(originalDuration, 2) + " -> " + fixed$(totalDuration, 2) + " s"

    # Original waveform.
    Select outer viewport: 0, 8, 0.62, 1.42
    Select inner viewport: 0.60, 7.70, 0.67, 1.37
    Axes: 0, originalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, originalDuration, 0
    selectObject: vizOriginal
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, originalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    # Tape result waveform.
    Select outer viewport: 0, 8, 1.48, 2.28
    Select inner viewport: 0.60, 7.70, 1.53, 2.23
    Axes: 0, totalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDuration, 0
    selectObject: vizResult
    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1
    Draw: 0, totalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Tape"
    Text bottom: "yes", "Time (s)"

    # --------------------------------------------------------------------------
    # USER-FACING PROCESS GRAPH: DEGRADATION ACROSS GENERATIONS
    # Two quantities are plotted because they share a meaningful 0..1 scale:
    #   - HF-edge retention: exact model response at Nyquist after N passes.
    #   - Print-through strength: actual ghost coefficient used per pass.
    # Memory and transport are explained beneath rather than put on a false
    # common axis, because they are coefficients / milliseconds / hertz.
    # --------------------------------------------------------------------------
    Select outer viewport: 0, 8, 2.45, 4.02
    Select inner viewport: 0.60, 7.70, 2.64, 3.72
    Axes: 0, generations + 1, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, generations + 1, 0, 1.05

    # Reference lines.
    Colour: "{0.86, 0.86, 0.86}"
    Dotted line
    Draw line: 0, 0.5, generations + 1, 0.5
    Draw line: 0, 1.0, generations + 1, 1.0
    Solid line

    # Generation ticks.
    Font size: 6
    Colour: "{0.45, 0.45, 0.45}"
    for genViz to generations
        Draw line: genViz, 0, genViz, 0.025
        if generations <= 12 or genViz = 1 or genViz = generations or genViz mod 2 = 0
            Text: genViz, "centre", 0.025, "half", string$(genViz)
        endif
    endfor

    # HF-edge retention across generations.
    Colour: "{0.80, 0.60, 0.20}"
    Line width: 2
    hfPrev = 1
    for genViz to generations
        hfNow = (1 - hf_loss_per_generation) ^ genViz
        if genViz = 1
            Draw line: 0, 1, 1, hfNow
        else
            Draw line: genViz - 1, hfPrev, genViz, hfNow
        endif
        hfPrev = hfNow
    endfor

    # Print-through strength, shown on its actual 0..1 coefficient scale.
    Colour: "{0.78, 0.28, 0.22}"
    Line width: 2
    printPrev = print_through_initial
    for genViz to generations
        printNow = print_through_initial * print_through_decay ^ (genViz - 1)
        if genViz > 1
            Draw line: genViz - 1, printPrev, genViz, printNow
        endif
        printPrev = printNow
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Degradation across generations"
    Text left: "yes", "Relative amount"
    Text bottom: "yes", "Tape generation"

    # Direct labels: no detached legend.
    Font size: 6
    Colour: "{0.80, 0.60, 0.20}"
    hfFinal = (1 - hf_loss_per_generation) ^ generations
    hfLabelY = max(0.22, min(1.01, hfFinal + 0.08))
    Text: generations - 0.05, "right", hfLabelY, "half",
        ... "HF-loss stage: " + fixed$(hfFinal * 100, 0) + "\%  edge retained"
    Colour: "{0.78, 0.28, 0.22}"
    printFinal = print_through_initial * print_through_decay ^ (generations - 1)
    printLabelY = max(0.08, printFinal + 0.06)
    Text: generations - 0.05, "right", printLabelY, "half",
        ... "Print ghost " + fixed$(print_through_initial, 2) + " -> " + fixed$(printFinal, 2)

    # Explanatory strip for mechanisms that use different units.
    Select outer viewport: 0, 8, 3.75, 4.18
    Select inner viewport: 0.60, 7.70, 3.79, 4.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.68, "half",
        ... "##Memory smear##  each pass blends " + fixed$(memoryPrevious * 100, 0) + "\%  from the previous sample"
    Text: 0.02, "left", 0.28, "half",
        ... "##Transport drift##  each pass adds wow " + fixed$(wow_depth_ms, 2) + " ms @ " + fixed$(wow_rate_Hz, 2) + " Hz + flutter " + fixed$(flutter_depth_ms, 2) + " ms @ " + fixed$(flutter_rate_Hz, 1) + " Hz"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Spectra: same roles, distinct output colour from the time-domain panel.
    Select outer viewport: 0, 4, 4.38, 5.78
    Select inner viewport: 0.60, 3.85, 4.53, 5.65
    selectObject: vizOriginal
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, spectrumMaxHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text top: "no", "Original spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    removeObject: origSpec

    Select outer viewport: 4, 8, 4.38, 5.78
    Select inner viewport: 4.45, 7.70, 4.53, 5.65
    selectObject: vizResult
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    Colour: "{0.35, 0.60, 0.40}"
    Draw: 0, spectrumMaxHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text top: "no", "Tape spectrum - progressive HF loss"
    Text bottom: "yes", "Frequency (Hz)"
    removeObject: resSpec

    # Summary strip.
    Select outer viewport: 0, 8, 5.98, 6.62
    Select inner viewport: 0.60, 7.70, 6.04, 6.56
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetDisplay$ + "##  " + string$(generations) + " generations"
        ... + " | HF loss/pass " + fixed$(hf_loss_per_generation * 100, 0) + "\% "
        ... + " | print-through " + fixed$(print_through_delay_ms, 0) + " ms, decay " + fixed$(print_through_decay, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "Memory " + fixed$(memoryCurrent, 2) + "/" + fixed$(memoryPrevious, 2)
        ... + " | tail " + fixed$(tail_duration_s, 1) + " s"
        ... + " | peak ceiling " + fixed$(scale_peak, 2)
        ... + " | output " + fixed$(totalDuration, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizOriginal, vizResult

    # Critical for reliable Save as PNG/EPS and clipboard export.
    Select outer viewport: 0, 8, 0, 6.80
endif

# ==============================================================================
# FINAL INFO
# ==============================================================================
selectObject: result
finalDuration = Get total duration
finalPeak = Get absolute extremum: 0, 0, "Sinc70"

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original: ", fixed$(originalDuration, 2), " s"
appendInfoLine: "Result: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
appendInfoLine: "Created: ", resultName$

if play_result
    selectObject: result
    Play
endif

selectObject: result
