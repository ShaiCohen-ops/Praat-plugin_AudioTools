# ============================================================
# Praat AudioTools - Hysteresis_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hysteresis Distortion — applies nonlinear distortion with
#   state memory: a static tanh saturation followed by a one-pole
#   IIR lag.
#
#   NAMING (v0.4): this is a hysteresis-LIKE dynamic nonlinear lag,
#   not a model of magnetic hysteresis. For any constant input
#   there is exactly one equilibrium, y = tanh((x + bias) * drive).
#   There is no coercivity, no remanence, no state-dependent
#   switching and no second stable branch, and if the input is
#   swept slowly enough the loop collapses onto that single tanh
#   curve. The ascending and descending paths differ only because
#   the IIR cannot keep up with a fast-changing input - which is
#   rate-dependent lag, not hysteresis. The effect is useful; the
#   claim of simulating tape or transformer physics is not
#   supportable, so it has been removed.
#
#   Math (per sample):
#     y[n] = (1 - mem) * tanh((x[n] + bias) * drive) + mem * y[n-1]
#
#   The script's signature behavior is the IIR memory term: the
#   output depends on the previous output, so ascending and
#   descending input traces produce different output trajectories
#   (the "loop").
#
#   Note that Hysteresis_Memory is a PER-SAMPLE coefficient, so
#   what it produces is tau = -1 / (fs * ln(m)) - measured in
#   samples, not musical time. At 44.1 kHz m = 0.9 gives 0.215 ms
#   and even m = 0.99, the maximum the coefficient mode allows,
#   gives only 2.26 ms. Use Memory_mode 2 to specify the time
#   constant directly; it is sample-rate independent and reaches
#   the range the preset names imply.
#
#   Implementation note: Praat's Formula iterates left-to-right
#   modifying `self` in place. Inside one formula evaluation,
#   bare `self` is the input value at the current column, while
#   `self[col-1]` returns the cell that has already been
#   overwritten with the output value at the previous column.
#   This Praat behavior is what makes the recursion work in a
#   single Formula pass.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - FIXED (the central mismatch): Hysteresis_Memory is a
#     per-sample coefficient, so the lag is tau = -1/(fs*ln(m)).
#     Measured at 44.1 kHz: m 0.10 -> 0.0098 ms, 0.25 -> 0.0164 ms,
#     0.30 -> 0.0188 ms, 0.75 -> 0.0788 ms, 0.90 -> 0.2152 ms,
#     0.99 -> 2.2562 ms. So the form's "0.9 = heavy lag" settles in
#     under a millisecond, Dark Transformer's 0.75 in a quarter of
#     one, and the 0.99 ceiling caps the whole effect at ~2.3 ms.
#     The same m also gives a different lag at every sample rate
#     (0.2152 ms at 44.1 kHz, 0.0989 ms at 96 kHz), so a preset was
#     not consistent across files. Memory_mode 2 takes the time
#     constant in ms and inverts m = exp(-1/(fs*tau)). Coefficient
#     mode remains the default, and the report now always states
#     the time the chosen coefficient actually gives.
#   - FIXED (multichannel recursion): the previous output was read
#     as `self[col-1]`, the one-index form, on a matrix object
#     where row is the channel. Written as `self[row, col - 1]`.
#     This is the same ambiguity that affected the resampling
#     read-back in Chaos_Distortion, and here it sits inside the
#     recursion, where a wrong reference cross-feeds channels.
#   - Output_level replaces the unconditional `Scale peak: 0.95`.
#     Output_Gain is a constant scalar, so normalizing divided it
#     straight back out - gains of 0.4, 0.8 and 2.0 gave identical
#     output. Normalize is still the default; the conditional
#     limiter is what makes the gain real. Silent-output guard
#     added, and the peak is now measured and reported.
#   - FIXED: the spectrum panel compared the original at its own
#     level with the result after normalization, so a source
#     peaking at 0.1 contributed nearly 20 dB of pure gain to what
#     was labelled harmonic enrichment. Matched by default.
#   - FIXED: the loop panel used a fixed 100 steps each way, and
#     each step advances the recursion by one sample - so the loop
#     was traced at fs/200, about 220 Hz at 44.1 kHz and 480 Hz at
#     96 kHz. Its width depended on the sample rate and on nPoints
#     and had no relation to the source. Loop_test_frequency_Hz is
#     now explicit and the step count derives from it.
#   - FIXED: restored the start/end time queries v0.3 removed as
#     "dead code", and every panel now uses the real time domain.
#     The "first 30 ms" zoom was querying 0..0.03 s regardless of
#     where the Sound actually sits.
#   - FIXED: memory clamping is reported. Entering 0.9999 to get a
#     slow memory silently became 0.99 - 227 ms of time constant
#     down to 2.26 ms, a hundredfold change, unannounced.
#   - RENAMED preset "Infinite Sustain (Limiter)" -> "Hard
#     Saturation Limiter". Its memory of 0.1 is the FASTEST of any
#     preset (tau ~0.01 ms), so the sustain does not come from the
#     hysteresis at all - it is drive 20 into a near-binary tanh
#     plus normalization. Object name changes to
#     _hysteresis_HardSatLimiter.
#   - Both headline panels are titled for the stage they show;
#     neither is the run's output transfer, since the audio
#     continues through Subtract mean, Output_Gain and the level
#     stage.
#   - Documented that the first sample initializes as y[0] = f(x[0])
#     rather than following the general recurrence - a deliberate
#     initial condition, but the equation and the code were not the
#     same statement.
#   - CORRECTED the description: this is hysteresis-LIKE dynamic
#     lag, not magnetic hysteresis (single equilibrium per input,
#     no coercivity or remanence, loop collapses under slow sweep).
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters: same recursive Formula, same
#     Subtract mean, same Output_Gain, same Scale peak.
#   - Form syntax modernized: optionmenu uses colon.
#   - Show_spectrum is now an opt-in form toggle (default OFF).
#     v0.2 always computed `To Spectrum: yes` on both original
#     and result for the visualization spectrum panel — that
#     can be a couple of seconds on long files. Default OFF
#     means the script runs as fast as v0.2's processing alone.
#     Turn ON to see the harmonic enrichment from saturation.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): hysteresis loop — the script's
#         most distinctive visual, showing the ascending vs
#         descending paths that diverge due to memory
#       Panel B (right, headline): static transfer function
#         (tanh curve with bias offset) for reference
#       Panel C: zoom overlay (original gray + distorted red,
#         first 30 ms) — replaces v0.2's two stacked waveform
#         panels with a single overlay
#       Panel D: output waveform (full file, L/R distinguished)
#       Panel E: summary stats bar
#   - Removed "dead" code (unused Get start time / Get end time).
#     [v0.4: they were not dead, only unused - and removing them
#     left every panel assuming the domain starts at 0. Restored.]
#   - Header documents the recursive-Formula trick that makes
#     the hysteresis math work in a single Praat pass.
# Changelog v0.2:
#   - Added transfer function visualization
#   - Improved info output
#   - Minor code cleanup
# ============================================================

# === Form ===
form Hysteresis Distortion v0.4
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Manual (use settings below)
        option Warm Tape Saturation
        option Dark Transformer
        option Offset Magnetics
        option Sluggish Fuzz
        option Hard Saturation Limiter

    comment === Parameters ===
    real Drive 2.0
    comment (1=subtle, 5=moderate, 10+=heavy)
    optionmenu Memory_mode: 1
        option Per-sample coefficient (v0.2/v0.3)
        option Time constant in ms (sample-rate independent)
    real Hysteresis_Memory 0.3
    comment (coefficient mode; see the report for the time it really gives)
    real Memory_time_ms 5.0
    comment (time-constant mode)
    real Asymmetry_Bias 0.0
    comment (0=symmetric, +/-0.3=asymmetric)
    real Output_Gain 0.9

    comment === Output ===
    optionmenu Output_level: 3
        option Preserve shaped level
        option Conditional limiter to 0.95
        option Normalize to 0.95 (v0.2/v0.3)
    boolean Show_spectrum 0
    comment (ON shows harmonic enrichment, but adds analysis time)
    optionmenu Spectrum_reference: 1
        option Matched peak (isolates harmonics)
        option Absolute rendered levels
    boolean Draw_visualization 1
    positive Loop_test_frequency_Hz 220
    comment (hysteresis loop panel: sweep rate to trace the loop at)
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# v0.4 (item 8): v0.3's changelog lists "Removed dead code (unused Get
# start time / Get end time)" - but they were not dead, they were
# unused, and every panel then assumed the domain starts at 0. A Sound
# extracted with times preserved sits at xmin..xmin+duration, so the
# "first 30 ms" zoom was querying a window with none of its data in it.
xminOrig = Get start time
xmaxOrig = Get end time

# === Handle Presets ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "WarmTape"
    drive = 1.5
    hysteresis_Memory = 0.25
    asymmetry_Bias = 0.0
    output_Gain = 0.95
elsif preset = 3
    presetName$ = "DarkTransformer"
    drive = 2.5
    hysteresis_Memory = 0.75
    asymmetry_Bias = 0.0
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "OffsetMagnetics"
    drive = 3.0
    hysteresis_Memory = 0.4
    asymmetry_Bias = 0.2
    output_Gain = 0.8
elsif preset = 5
    presetName$ = "SluggishFuzz"
    drive = 10.0
    hysteresis_Memory = 0.5
    asymmetry_Bias = 0.05
    output_Gain = 0.5
elsif preset = 6
    # v0.4 (item 6): was "Infinite Sustain (Limiter)" / "InfiniteSustain".
    # Its memory of 0.1 is the FASTEST setting of any preset - a time
    # constant near 0.01 ms, i.e. essentially no memory at all - so the
    # sustain does not come from the hysteresis at all. What it actually
    # does is drive 20 into a near-binary tanh and normalize. Named for
    # that. Output object name changes from _hysteresis_InfiniteSustain
    # to _hysteresis_HardSatLimiter.
    presetName$ = "HardSatLimiter"
    drive = 20.0
    hysteresis_Memory = 0.1
    asymmetry_Bias = 0.0
    output_Gain = 0.4
endif

# === Memory resolution ===
# v0.4 CRITICAL (item 1): Hysteresis_Memory is a PER-SAMPLE coefficient,
# so the lag it produces is tau = -1 / (fs * ln(m)) - a quantity in
# samples, not in musical time. At 44.1 kHz that makes the presets far
# faster than their names suggest:
#     m = 0.10 (Hard Sat Limiter) -> tau 0.0098 ms
#     m = 0.25 (Warm Tape)        -> tau 0.0164 ms
#     m = 0.30 (form default)     -> tau 0.0188 ms
#     m = 0.75 (Dark Transformer) -> tau 0.0788 ms  (95% in 0.24 ms)
#     m = 0.90 (form's "heavy lag") -> tau 0.2152 ms
#     m = 0.99 (the maximum allowed) -> tau 2.2562 ms
# So "heavy lag" settles in under a millisecond, and even the ceiling
# the script permits is ~2.3 ms - this is a few-sample smoother, not
# transformer inertia. Worse, the same m gives a different lag at every
# sample rate (0.2152 ms at 44.1 kHz, 0.0989 ms at 96 kHz), so a preset
# is not consistent across files.
# Memory_mode 2 takes the time constant directly and inverts
# m = exp(-1 / (fs * tau)), which is sample-rate independent and reaches
# the range the names imply. Coefficient mode stays the default so v0.3
# renders reproduce.
memNotes$ = ""
memReq = hysteresis_Memory

if memory_mode = 2
    if memory_time_ms <= 0
        exitScript: "Memory_time_ms must be above 0."
    endif
    hysteresis_Memory = exp(-1 / (sr * memory_time_ms / 1000))
    memDesc$ = "time constant " + fixed$(memory_time_ms, 3) + " ms (coefficient " + fixed$(hysteresis_Memory, 7) + ")"
else
    # v0.4 (item 7): v0.3 rewrote out-of-range values silently. The
    # 0.99 ceiling is the damaging one: a user entering 0.9999 to get a
    # slow memory got 0.99 instead, dropping the time constant from
    # 227 ms to 2.26 ms - a hundredfold change, unannounced.
    if hysteresis_Memory >= 1.0
        hysteresis_Memory = 0.99
        memNotes$ = memNotes$ + "  NOTE: Hysteresis_Memory of " + fixed$(memReq, 6)
            ... + " was reduced to 0.99 for stability. That is a large change: "
            ... + fixed$(memReq, 6) + " would give a time constant of "
            ... + fixed$(-1 / (sr * ln(memReq)) * 1000, 2) + " ms, while 0.99 gives "
            ... + fixed$(-1 / (sr * ln(0.99)) * 1000, 2) + " ms. Use Memory_mode 2 to set the time directly." + newline$
    endif
    if hysteresis_Memory < 0
        hysteresis_Memory = 0
        memNotes$ = memNotes$ + "  NOTE: Hysteresis_Memory of " + fixed$(memReq, 4) + " was raised to 0 (negative memory is unstable)." + newline$
    endif
    if hysteresis_Memory > 0
        memTau = -1 / (sr * ln(hysteresis_Memory)) * 1000
        memDesc$ = "coefficient " + fixed$(hysteresis_Memory, 4) + " (time constant " + fixed$(memTau, 4) + " ms at " + fixed$(sr, 0) + " Hz)"
    else
        memDesc$ = "coefficient 0 (no memory - static tanh)"
    endif
endif

if hysteresis_Memory > 0
    memTau = -1 / (sr * ln(hysteresis_Memory)) * 1000
else
    memTau = 0
endif

# === Info ===
writeInfoLine: "=== Hysteresis Distortion v0.4 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch, starts at ", fixed$(xminOrig, 3), " s)"
appendInfoLine: "Preset: ", presetName$
if memNotes$ <> ""
    appendInfoLine: memNotes$
endif
appendInfoLine: ""
appendInfoLine: "Drive: ", fixed$(drive, 2)
appendInfoLine: "Memory: ", memDesc$
if hysteresis_Memory > 0
    appendInfoLine: "  95% settling: ", fixed$(memTau * 3, 4), " ms"
endif
appendInfoLine: "Bias: ", fixed$(asymmetry_Bias, 3)
appendInfoLine: "Output gain: ", fixed$(output_Gain, 2)
appendInfoLine: ""

# ============================================================
# PROCESSING (identical to v0.2)
# ============================================================

appendInfoLine: "Applying hysteresis distortion..."

selectObject: original
Copy: origName$ + "_Hyst_" + presetName$
result = selected("Sound")

# Build formula strings for the recursive processing
d_str$ = string$(drive)
m_str$ = string$(hysteresis_Memory)
inv_m_str$ = string$(1.0 - hysteresis_Memory)
b_str$ = string$(asymmetry_Bias)

# Nonlinear component (static tanh saturation with bias)
nonlin$ = "tanh((self + " + b_str$ + ") * " + d_str$ + ")"

# Recursive formula:
#   col = 1 has no previous sample
#   col > 1 -> nonlinear blended with previous output
#
# v0.4 (item 10): the header states y[n] = (1-m)f(x[n]) + m*y[n-1], but
# the first sample is y[0] = f(x[0]), NOT (1-m)f(x[0]) + m*y[-1]. That is
# a deliberate and sensible initial condition - it starts the state on
# the nonlinearity rather than at zero, so a file beginning at a constant
# level has no start-up transient - but the equation and the code were
# not the same statement. Documented rather than changed.
#
# v0.4 (item 11): the previous output was read as `self[col-1]`, the
# ONE-index form. A Sound is a matrix in which row is the channel and
# col the sample, and the documented sample accessor is self[row, col] -
# so on multichannel input the one-index form does not clearly refer to
# the current channel's previous sample. This is the same ambiguity that
# affected the resampling read-back in Chaos_Distortion, and here it sits
# inside the recursion itself, where a wrong reference would cross-feed
# channels. Written explicitly as self[row, col - 1].
formula$ = "if col = 1 then " + nonlin$ + " else (" + nonlin$ + " * " + inv_m_str$ + ") + (self[row, col - 1] * " + m_str$ + ") fi"

# Apply hysteresis
selectObject: result
Formula: formula$

# Remove DC offset introduced by the recursive filter
Subtract mean

# Output gain
Formula: ~ self * output_Gain

# === Output level ===
# v0.4 (item 2): v0.3 always ran `Scale peak: 0.95` straight after
# multiplying by Output_Gain. Since the gain is a constant scalar,
# normalizing divides it back out - 0.95*g*y / max|g*y| = 0.95*y /
# max|y| for every non-zero g - so gains of 0.4, 0.8 and 2.0 gave
# identical output. The parameter was displayed and reported while
# controlling nothing. Normalize stays the default so v0.3 renders
# reproduce; the conditional limiter is the setting that makes
# Output_Gain real.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"

levelScale = 1
if output_level = 1
    levelDesc$ = "preserved"
elsif output_level = 2
    if prePeak > 0.95
        selectObject: result
        Scale peak: 0.95
        levelScale = 0.95 / prePeak
        levelDesc$ = "limited to 0.95"
    else
        levelDesc$ = "unchanged (below 0.95)"
    endif
else
    if prePeak > 0
        selectObject: result
        Scale peak: 0.95
        levelScale = 0.95 / prePeak
        levelDesc$ = "normalized to 0.95"
    else
        levelDesc$ = "silent output - scaling skipped"
    endif
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalMean = Get mean: 0, 0, 0
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

if nResultCh = 1
    chanLegend$ = "(mono)"
elsif nResultCh = 2
    chanLegend$ = "(blue=ch1  orange=ch2)"
else
    chanLegend$ = "(first 2 of " + string$(nResultCh) + " channels shown)"
endif

appendInfoLine: "Peak before output stage: ", fixed$(prePeak, 4)
appendInfoLine: "Output level: ", levelDesc$
appendInfoLine: "Measured output peak: ", fixed$(finalPeak, 4)
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - above 1.0 it will clip on playback or export."
endif
if output_level = 3
    appendInfoLine: "  NOTE: peak normalization removes the MAGNITUDE of Output_Gain; a negative gain still inverts the output."
endif
appendInfoLine: ""

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # Compute spectra ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrum
        appendInfoLine: "Computing spectra for visualization..."
        
        # Original spectrum (mono for fair comparison)
        selectObject: original
        if input_n_channels > 1
            specSrcOrig = Convert to mono
        else
            selectObject: original
            specSrcOrig = Copy: "specSrcOrig"
        endif
        # Result spectrum
        selectObject: result
        if nResultCh > 1
            specSrcRes = Convert to mono
        else
            selectObject: result
            specSrcRes = Copy: "specSrcRes"
        endif
        
        # v0.4 (item 3): v0.3 took the original at its own level and the
        # result AFTER `Scale peak: 0.95`, so the panel labelled
        # "harmonic enrichment" also carried the whole normalization
        # gain. A source peaking at 0.1 is lifted nearly 9.5x - close to
        # 20 dB of difference that has nothing to do with saturation.
        # Both sides are matched by default.
        if spectrum_reference = 1
            selectObject: specSrcOrig
            oPk = Get absolute extremum: 0, 0, "None"
            if oPk > 0
                Scale peak: 0.95
            endif
            selectObject: specSrcRes
            rPk = Get absolute extremum: 0, 0, "None"
            if rPk > 0
                Scale peak: 0.95
            endif
            specRefLabel$ = "matched peak"
        else
            specRefLabel$ = "absolute levels"
        endif
        
        selectObject: specSrcOrig
        specOrig = To Spectrum: "yes"
        Rename: "specOrig"
        specOrigID = selected("Spectrum")
        removeObject: specSrcOrig
        
        selectObject: specSrcRes
        specRes = To Spectrum: "yes"
        Rename: "specRes"
        specResID = selected("Spectrum")
        removeObject: specSrcRes
    else
        specRefLabel$ = ""
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##HYSTERESIS DISTORTION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... origName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Memory: " + fixed$(hysteresis_Memory, 2)
        ... + "  |  Bias: " + fixed$(asymmetry_Bias, 2)
        ... + "  |  Gain: " + fixed$(output_Gain, 2)
    
    # ----------------------------------------------------------
    # PANEL A: HYSTERESIS LOOP  (left, headline)
    # The defining diagnostic for this script — ascending vs
    # descending input paths diverge due to memory.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # ±1 saturation reference
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: -1.2, 1, 1.2, 1
    Draw line: -1.2, -1, 1.2, -1
    Solid line
    
    # Identity reference
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Simulate hysteresis loop
    # v0.4 (item 5): v0.3 used a fixed 100 steps up and 100 down, and
    # each step advances the recursion by exactly one sample - so the
    # loop was traced at fs/200, about 220 Hz at 44.1 kHz and about
    # 480 Hz at 96 kHz. The drawn loop width therefore depended on the
    # file's sample rate and on nPoints, and had no relation to any
    # frequency present in the source. The sweep rate is now an explicit
    # parameter and the step count derives from it, so the loop means
    # "what the memory does to a sweep at THIS frequency".
    nPoints = round(sr / loop_test_frequency_Hz / 2)
    if nPoints < 8
        nPoints = 8
    endif
    if nPoints > 20000
        nPoints = 20000
    endif
    loopFreqActual = sr / (nPoints * 2)
    
    # Pre-warm the loop with one forward pass to establish prevY
    # at a stable point (so first visible cycle isn't a transient)
    prevY = 0
    for warmPass from 1 to 3
        for p from 1 to nPoints
            x = -1.0 + (p - 1) / nPoints * 2.0
            newInput = tanh((x + asymmetry_Bias) * drive)
            prevY = (1 - hysteresis_Memory) * newInput + hysteresis_Memory * prevY
        endfor
        for p from 1 to nPoints
            x = 1.0 - (p - 1) / nPoints * 2.0
            newInput = tanh((x + asymmetry_Bias) * drive)
            prevY = (1 - hysteresis_Memory) * newInput + hysteresis_Memory * prevY
        endfor
    endfor
    
    # Now draw one full cycle: ascending then descending
    # Ascending path (blue)
    Colour: "{0.30, 0.45, 0.78}"
    Line width: 1.8
    for p from 1 to nPoints
        x = -1.0 + (p - 1) / nPoints * 2.0
        newInput = tanh((x + asymmetry_Bias) * drive)
        y = (1 - hysteresis_Memory) * newInput + hysteresis_Memory * prevY
        if p > 1
            prevX = -1.0 + (p - 2) / nPoints * 2.0
            Draw line: prevX, prevY, x, y
        endif
        prevY = y
    endfor
    
    # Descending path (red)
    Colour: "{0.78, 0.40, 0.40}"
    Line width: 1.8
    for p from 1 to nPoints
        x = 1.0 - (p - 1) / nPoints * 2.0
        newInput = tanh((x + asymmetry_Bias) * drive)
        y = (1 - hysteresis_Memory) * newInput + hysteresis_Memory * prevY
        if p > 1
            prevX = 1.0 - (p - 2) / nPoints * 2.0
            Draw line: prevX, prevY, x, y
        endif
        prevY = y
    endfor
    Line width: 1
    
    # Legend
    Font size: 5
    Colour: "{0.30, 0.45, 0.78}"
    Text: -1.15, "left", 1.10, "half", "blue = ascending"
    Colour: "{0.78, 0.40, 0.40}"
    Text: -1.15, "left", 1.00, "half", "red = descending"
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    if hysteresis_Memory < 0.05
        Text: 1.15, "right", 1.10, "half", "no loop (mem~0)"
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: STATIC TRANSFER FUNCTION  (right, headline)
    # The non-recursive tanh curve, for reference.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # ±1 saturation reference
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: -1.2, 1, 1.2, 1
    Draw line: -1.2, -1, 1.2, -1
    Solid line
    
    # Identity reference
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Bias offset reference (vertical line at x = -bias, where
    # the tanh's argument crosses zero)
    if abs(asymmetry_Bias) > 0.001
        biasLine = -asymmetry_Bias
        if biasLine >= -1.2 and biasLine <= 1.2
            Colour: "{0.55, 0.78, 0.55}"
            Dotted line
            Draw line: biasLine, -1.2, biasLine, 1.2
            Solid line
            Font size: 5
            Colour: "{0.30, 0.55, 0.30}"
            Text: biasLine, "left", -1.10, "half", " bias"
        endif
    endif
    
    # Static tanh curve
    Colour: "{0.40, 0.65, 0.45}"
    Line width: 2
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh((x1 + asymmetry_Bias) * drive)
        y2 = tanh((x2 + asymmetry_Bias) * drive)
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    # v0.4 (item 9): neither panel is the run's output transfer. The
    # audio continues through Subtract mean (a file-dependent vertical
    # shift), Output_Gain, and the output level stage. Both titles now
    # say which stage they show, and the loop names its sweep rate,
    # since the loop width is a function of that rate (item 5).
    Text: 2.10, "centre", 7.30, "half", "Recursive loop at " + fixed$(loopFreqActual, 0) + " Hz sweep (before mean removal + level)"
    Text: 6.10, "centre", 7.30, "half", "Static tanh stage (before memory, mean removal + level)"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (full width, first 30 ms)
    # OR SPECTRUM if Show_spectrum is ON.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    if show_spectrum
        # ==== SPECTRUM COMPARISON ====
        maxFreqDisplay = sr / 2
        if maxFreqDisplay > 8000
            maxFreqDisplay = 8000
        endif
        
        Axes: 0, maxFreqDisplay, 0, 80
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxFreqDisplay, 0, 80
        
        # Light frequency gridlines
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        gridF = 1000
        while gridF < maxFreqDisplay
            Draw line: gridF, 0, gridF, 80
            Font size: 5
            Colour: "{0.55, 0.55, 0.55}"
            if gridF < 1000
                Text: gridF, "centre", 3, "half", string$(gridF)
            else
                Text: gridF, "centre", 3, "half", fixed$(gridF / 1000, 0) + "k"
            endif
            Colour: "{0.88, 0.88, 0.92}"
            gridF = gridF + 1000
        endwhile
        
        # Original (gray, behind)
        selectObject: specOrigID
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1.2
        Draw: 0, maxFreqDisplay, 0, 80, "no"
        
        # Result (red, on top)
        selectObject: specResID
        Colour: "{0.78, 0.40, 0.40}"
        Line width: 1.5
        Draw: 0, maxFreqDisplay, 0, 80, "no"
        Line width: 1
        
        # Legend
        Font size: 5
        Colour: "{0.65, 0.65, 0.65}"
        Text: maxFreqDisplay * 0.99, "right", 73, "half", "gray = original "
        Colour: "{0.78, 0.40, 0.40}"
        Text: maxFreqDisplay * 0.99, "right", 65, "half", "red = distorted "
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Spectrum: original vs distorted (" + specRefLabel$ + ")"
        Text left: "yes", "Power (dB)"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # ==== ZOOM OVERLAY ====
        zoomDur = 0.03
        if zoomDur > duration
            zoomDur = duration
        endif
        
        selectObject: original
        zoomStart = xminOrig
        zoomEnd = xminOrig + zoomDur
        origPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
        selectObject: result
        resPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
        zoomMax = origPeak
        if resPeak > zoomMax
            zoomMax = resPeak
        endif
        if zoomMax < 0.001
            zoomMax = 0.001
        endif
        zAmpViz = zoomMax * 1.15
        
        Axes: zoomStart, zoomEnd, -zAmpViz, zAmpViz
        Paint rectangle: "{0.97, 0.97, 0.97}", zoomStart, zoomEnd, -zAmpViz, zAmpViz
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: zoomStart, 0, zoomEnd, 0
        
        # Original (gray, behind)
        selectObject: original
        if input_n_channels > 1
            Extract one channel: 1
            zOrig = selected("Sound")
            Colour: "{0.65, 0.65, 0.65}"
            Line width: 1
            Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
            removeObject: zOrig
        else
            Colour: "{0.65, 0.65, 0.65}"
            Line width: 1
            Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        endif
        
        # Distorted (red, on top)
        selectObject: result
        if nResultCh > 1
            Extract one channel: 1
            zRes = selected("Sound")
            Colour: "{0.78, 0.40, 0.40}"
            Line width: 1.3
            Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
            removeObject: zRes
        else
            Colour: "{0.78, 0.40, 0.40}"
            Line width: 1.3
            Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        endif
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, red = distorted)"
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
    endif
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: xminOrig, xmaxOrig, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: xminOrig, 0, xmaxOrig, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: "{0.78, 0.40, 0.40}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nResultCh >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output (full file)  " + chanLegend$
    else
        Text top: "no", "Output (full file, mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if show_spectrum
        spectrumStr$ = "shown"
    else
        spectrumStr$ = "off (Show_spectrum = ON to see)"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + origName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Memory: " + fixed$(hysteresis_Memory, 3)
        ... + "  |  Bias: " + fixed$(asymmetry_Bias, 3)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Output gain: " + fixed$(output_Gain, 2)
        ... + "  |  Spectrum panel: " + spectrumStr$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectrum objects if computed
    if show_spectrum
        removeObject: specOrigID, specResID
    endif
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
