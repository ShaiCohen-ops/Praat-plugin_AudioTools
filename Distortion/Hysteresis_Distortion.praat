# ============================================================
# Praat AudioTools - Hysteresis_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hysteresis Distortion — applies nonlinear distortion with
#   state memory. Simulates magnetic tape saturation, transformer
#   core lag, and analog circuit inertia.
#
#   Math (per sample):
#     y[n] = (1 - mem) * tanh((x[n] + bias) * drive) + mem * y[n-1]
#
#   The script's signature behavior is the IIR memory term: the
#   output depends on the previous output, so ascending and
#   descending input traces produce different output trajectories
#   (the "hysteresis loop"). High memory values produce sluggish
#   response and DC drift; low memory acts almost like a static
#   tanh saturation.
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
#   - Removed dead code (unused Get start time / Get end time).
#   - Header documents the recursive-Formula trick that makes
#     the hysteresis math work in a single Praat pass.
# Changelog v0.2:
#   - Added transfer function visualization
#   - Improved info output
#   - Minor code cleanup
# ============================================================

# === Form ===
form Hysteresis Distortion v0.3
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Manual (use settings below)
        option Warm Tape Saturation
        option Dark Transformer
        option Offset Magnetics
        option Sluggish Fuzz
        option Infinite Sustain (Limiter)

    comment === Parameters ===
    real Drive 2.0
    comment (1=subtle, 5=moderate, 10+=heavy)
    real Hysteresis_Memory 0.3
    comment (0=no memory, 0.9=heavy lag)
    real Asymmetry_Bias 0.0
    comment (0=symmetric, +/-0.3=asymmetric)
    real Output_Gain 0.9

    comment === Output ===
    boolean Show_spectrum 0
    comment (ON shows harmonic enrichment, but adds analysis time)
    boolean Draw_visualization 1
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
    presetName$ = "InfiniteSustain"
    drive = 20.0
    hysteresis_Memory = 0.1
    asymmetry_Bias = 0.0
    output_Gain = 0.4
endif

# Safety check — memory must be < 1 for stability
if hysteresis_Memory >= 1.0
    hysteresis_Memory = 0.99
endif
if hysteresis_Memory < 0
    hysteresis_Memory = 0
endif

# === Info ===
writeInfoLine: "=== Hysteresis Distortion v0.3 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drive: ", fixed$(drive, 2)
appendInfoLine: "Memory: ", fixed$(hysteresis_Memory, 3)
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
#   col = 1 has no previous sample → just nonlinear
#   col > 1 → nonlinear blended with previous output (self[col-1])
formula$ = "if col = 1 then " + nonlin$ + " else (" + nonlin$ + " * " + inv_m_str$ + ") + (self[col-1] * " + m_str$ + ") fi"

# Apply hysteresis
selectObject: result
Formula: formula$

# Remove DC offset introduced by the recursive filter
Subtract mean

# Output gain
Formula: ~ self * output_Gain

# Final scale to prevent clipping
Scale peak: 0.95

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

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
        selectObject: specSrcOrig
        specOrig = To Spectrum: "yes"
        Rename: "specOrig"
        specOrigID = selected("Spectrum")
        removeObject: specSrcOrig
        
        # Result spectrum
        selectObject: result
        if nResultCh > 1
            specSrcRes = Convert to mono
        else
            selectObject: result
            specSrcRes = Copy: "specSrcRes"
        endif
        selectObject: specSrcRes
        specRes = To Spectrum: "yes"
        Rename: "specRes"
        specResID = selected("Spectrum")
        removeObject: specSrcRes
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
    nPoints = 100
    
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
    Text: 2.10, "centre", 7.30, "half", "Hysteresis loop (memory effect)"
    Text: 6.10, "centre", 7.30, "half", "Static transfer (tanh, no memory)"
    
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
        Text top: "no", "Spectrum: original vs distorted"
        Text left: "yes", "Power (dB)"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # ==== ZOOM OVERLAY ====
        zoomDur = 0.03
        if zoomDur > duration
            zoomDur = duration
        endif
        
        selectObject: original
        origPeak = Get absolute extremum: 0, zoomDur, "None"
        selectObject: result
        resPeak = Get absolute extremum: 0, zoomDur, "None"
        zoomMax = origPeak
        if resPeak > zoomMax
            zoomMax = resPeak
        endif
        if zoomMax < 0.001
            zoomMax = 0.001
        endif
        zAmpViz = zoomMax * 1.15
        
        Axes: 0, zoomDur, -zAmpViz, zAmpViz
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -zAmpViz, zAmpViz
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, zoomDur, 0
        
        # Original (gray, behind)
        selectObject: original
        if input_n_channels > 1
            Extract one channel: 1
            zOrig = selected("Sound")
            Colour: "{0.65, 0.65, 0.65}"
            Line width: 1
            Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
            removeObject: zOrig
        else
            Colour: "{0.65, 0.65, 0.65}"
            Line width: 1
            Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        endif
        
        # Distorted (red, on top)
        selectObject: result
        if nResultCh > 1
            Extract one channel: 1
            zRes = selected("Sound")
            Colour: "{0.78, 0.40, 0.40}"
            Line width: 1.3
            Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
            removeObject: zRes
        else
            Colour: "{0.78, 0.40, 0.40}"
            Line width: 1.3
            Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
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
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
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
        Text top: "no", "Output (full file)  (blue=L  orange=R)"
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
