# ============================================================
# Praat AudioTools - Full-Wave_Rectifier_Abs.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Full-Wave Rectifier — applies abs() to the input, flipping
#   negative samples to positive. Classic analog effect that
#   doubles the perceived fundamental frequency and introduces
#   strong even harmonics (2f, 4f, 6f...). The output is
#   characteristically buzzy and aggressive.
#
#   Stereo input is processed per-channel — both channels
#   rectified independently. Output preserves the input's
#   channel count.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters: Formula: ~ abs(self) +
#     Scale peak.
#   - Form syntax modernized: optionmenu uses colon.
#   - Show_spectrum is now an opt-in form toggle (default OFF).
#     v0.2 always computed `To Spectrum: yes` on both original
#     and rectified for the visualization spectrum panel — that
#     can be a couple of seconds on long files. Default OFF
#     means the script runs in milliseconds. Turn ON when you
#     want to see the harmonic enrichment (which is the whole
#     point of rectification, so worth seeing occasionally).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): abs() transfer function
#       Panel B (right, headline): spectrum comparison if
#         Show_spectrum=ON, else parameter report
#       Panel C: zoom overlay (original gray + rectified green)
#         showing the negative-half flip directly
#       Panel D: output waveform (full file, L/R distinguished)
#       Panel E: summary stats bar
# Changelog v0.2:
#   - Fixed input check
#   - Added visualization
#   - Added info output
# ============================================================

form Full-Wave Rectifier v0.3
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Default (0.95 peak)
        option Soft (0.8 peak)
        option Maximum (1.0 peak)
        option Custom (use setting below)
    
    comment === Output ===
    positive Scale_peak 0.95
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
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# === Apply Presets ===
if preset = 1
    scale_peak = 0.95
    presetName$ = "Default"
elsif preset = 2
    scale_peak = 0.8
    presetName$ = "Soft"
elsif preset = 3
    scale_peak = 1.0
    presetName$ = "Maximum"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Full-Wave Rectifier v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Scale peak: ", fixed$(scale_peak, 3)
appendInfoLine: ""
appendInfoLine: "Effect: y = |x|  (negative -> positive)"
appendInfoLine: "Result: 2x perceived fundamental, even harmonics"
appendInfoLine: ""

# ============================================================
# PROCESSING  (identical to v0.2)
# ============================================================

appendInfoLine: "Applying rectification..."

selectObject: original
Copy: originalName$ + "_rectified_" + presetName$
result = selected("Sound")

selectObject: result
Formula: ~ abs(self)
Scale peak: scale_peak

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
        
        # Original spectrum (use mono for fair comparison)
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
        specRect = To Spectrum: "yes"
        Rename: "specRect"
        specRectID = selected("Spectrum")
        removeObject: specSrcRes
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##FULL-WAVE RECTIFIER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  Scale peak: " + fixed$(scale_peak, 3)
        ... + "  |  Effect: y = |x|"
        ... + "  |  " + string$(input_n_channels) + " ch input -> " + string$(nResultCh) + " ch output"
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic. y = |x| is a V-shape.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.2, 1.2, -0.3, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -0.3, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -0.3, 0, 1.2
    
    # Linear y=x reference (positive side) — what NO rectification would look like
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: 0, 0, 1, 1
    Draw line: -1, -1, 0, 0
    Solid line
    
    # The abs() transfer function — V shape
    Colour: "{0.40, 0.65, 0.45}"
    Line width: 2.5
    # Negative half: flipped to positive
    Draw line: -1, 1, 0, 0
    # Positive half: unchanged
    Draw line: 0, 0, 1, 1
    Line width: 1
    
    # Annotations
    Font size: 5
    Colour: "{0.30, 0.55, 0.30}"
    Text: -0.5, "centre", 0.55, "half", " |x| "
    Text: 0.5, "centre", 0.55, "half", " x "
    
    # Identity reference label
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    Text: -0.95, "left", -0.20, "half", "(dotted = identity)"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: SPECTRUM COMPARISON or PARAMETER REPORT  (right)
    # Conditional on Show_spectrum form toggle.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    if show_spectrum
        # ==== SPECTRUM COMPARISON ====
        maxFreqDisplay = sr / 2
        if maxFreqDisplay > 5000
            maxFreqDisplay = 5000
        endif
        
        Axes: 0, maxFreqDisplay, 0, 80
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxFreqDisplay, 0, 80
        
        # Light frequency gridlines (every 1 kHz)
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
        
        # Original spectrum (gray, behind)
        selectObject: specOrigID
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1.2
        Draw: 0, maxFreqDisplay, 0, 80, "no"
        
        # Rectified spectrum (green, on top)
        selectObject: specRectID
        Colour: "{0.40, 0.65, 0.45}"
        Line width: 1.5
        Draw: 0, maxFreqDisplay, 0, 80, "no"
        Line width: 1
        
        # Legend
        Font size: 5
        Colour: "{0.55, 0.55, 0.55}"
        Text: maxFreqDisplay * 0.99, "right", 73, "half", "gray = original "
        Colour: "{0.40, 0.65, 0.45}"
        Text: maxFreqDisplay * 0.99, "right", 65, "half", "green = rectified "
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Power (dB)"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # ==== PARAMETER REPORT ====
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.92, "half", "Operation:"
        
        Font size: 13
        Colour: "{0.40, 0.65, 0.45}"
        Text: 0.10, "left", 0.82, "half", "y = |x|"
        
        Font size: 8
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.74, "half", "(absolute value, sample-by-sample)"
        
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.62, "half", "Output:"
        
        Font size: 11
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.10, "left", 0.54, "half", "Peak:    " + fixed$(scale_peak, 3)
        Text: 0.10, "left", 0.46, "half", "Channels: " + string$(nResultCh)
        Text: 0.10, "left", 0.38, "half", "Duration: " + fixed$(finalDur, 2) + " s"
        
        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.27, "half", "Spectral effect:"
        
        Font size: 8
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.19, "half", "Doubles perceived fundamental"
        Text: 0.10, "left", 0.11, "half", "Adds strong even harmonics"
        
        Font size: 6
        Colour: "{0.78, 0.50, 0.30}"
        Text: 0.05, "left", 0.03, "half", "(Show_spectrum = ON to see this)"
        
        Colour: "Black"
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Transfer function (V-shape)"
    if show_spectrum
        Text: 6.10, "centre", 7.30, "half", "Spectrum: original vs rectified"
    else
        Text: 6.10, "centre", 7.30, "half", "Operation summary"
    endif
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (full width, first 20 ms)
    # Original (gray) + rectified (green) overlaid.
    # The visual signature of full-wave rectification: the
    # below-zero portion of the original is reflected upward.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.02
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
    
    # Rectified (green, on top)
    selectObject: result
    if nResultCh > 1
        Extract one channel: 1
        zRes = selected("Sound")
        Colour: "{0.40, 0.65, 0.45}"
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zRes
    else
        Colour: "{0.40, 0.65, 0.45}"
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, green = rectified)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
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
        Colour: "{0.40, 0.65, 0.45}"
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
        ... + "  " + originalName$
        ... + "  |  Operation: y = |x|"
        ... + "  |  Scale peak: " + fixed$(scale_peak, 3)
        ... + "  |  Channels: " + string$(input_n_channels) + " -> " + string$(nResultCh)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Spectrum panel: " + spectrumStr$
        ... + "  |  Effect: doubles fundamental + even harmonics"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectrum objects if computed
    if show_spectrum
        removeObject: specOrigID, specRectID
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
