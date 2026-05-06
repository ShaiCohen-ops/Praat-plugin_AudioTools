# ============================================================
# Praat AudioTools - Dynamic_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic Distortion (Envelope Follower) — applies tanh
#   saturation where the drive amount is modulated by the input
#   signal's amplitude envelope. Loud sections get more
#   distortion; quiet sections stay cleaner. Like a
#   touch-sensitive overdrive.
#
#   Pipeline:
#     1. Build envelope: rectify (abs), then low-pass filter at
#        Response_Speed_Hz to smooth out high-frequency content
#     2. Per-sample drive = base_Drive + envelope * sensitivity
#     3. Output = tanh(input * drive) * output_Gain
#
#   Stereo input is collapsed to mono before processing — this
#   script produces a mono output regardless of input channels.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. Speed matches v0.2.
#   - Architectural cleanup: replaced v0.2's "stereo container"
#     trick (audio in row 1, envelope in row 2 of a single Sound,
#     formula reads object[container, 2, col] from the same object
#     it's modifying) with explicit cross-Sound reference to a
#     separate envelope object. Same audio result; safer pattern
#     that doesn't depend on Praat's row-iteration order. Also
#     removes one Convert-to-mono call (v0.2 did it twice).
#   - Form syntax modernized: optionmenu uses colon.
#   - Removed dead code (unused Get start time / Get end time).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): transfer function with two
#         overlaid curves — quiet (gray, base drive) and loud
#         (red, base + sens*0.5 drive). The visual fingerprint
#         of "what this script does."
#       Panel B (right, headline): envelope + computed drive
#         over time, color-coded
#       Panel C: original vs result waveform (overlaid, gray
#         original + red result)
#       Panel D: output waveform (full file)
#       Panel E: summary stats bar
#   - Header documents the mono-collapse behavior (input goes
#     through Convert to mono regardless of channel count).
# Changelog v0.2:
#   - Fixed object reference (use ID instead of name)
#   - Added drive curve visualization
#   - Improved info output
# ============================================================

# === Form ===
form Dynamic Distortion v0.3
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Manual (use settings below)
        option Touch Sensitive Drive
        option Drum Pumper
        option Gated Crunch
        option Expressive Lead

    comment === Envelope Follower ===
    real Base_Drive 1.0
    comment (minimum drive when quiet)
    real Sensitivity 5.0
    comment (how much envelope adds to drive)
    real Response_Speed_Hz 20.0
    comment (higher = faster response, lower = smoother)

    comment === Output ===
    real Output_Gain 0.9
    
    comment === Visualization ===
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
    presetName$ = "TouchSensitive"
    base_Drive = 0.8
    sensitivity = 3.0
    response_Speed_Hz = 15.0
    output_Gain = 0.9
elsif preset = 3
    presetName$ = "DrumPumper"
    base_Drive = 1.0
    sensitivity = 8.0
    response_Speed_Hz = 50.0
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "GatedCrunch"
    # Negative base drive acts like a gate/expander before distorting
    base_Drive = -0.5 
    sensitivity = 10.0
    response_Speed_Hz = 80.0
    output_Gain = 1.0
elsif preset = 5
    presetName$ = "ExpressiveLead"
    base_Drive = 1.2
    sensitivity = 4.0
    response_Speed_Hz = 10.0
    output_Gain = 0.9
endif

# === Info ===
writeInfoLine: "=== Dynamic Distortion v0.3 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Base drive: ", fixed$(base_Drive, 2)
appendInfoLine: "Sensitivity: ", fixed$(sensitivity, 2)
appendInfoLine: "Response: ", fixed$(response_Speed_Hz, 1), " Hz"
appendInfoLine: "Output gain: ", fixed$(output_Gain, 2)
appendInfoLine: ""

# === Step 1: Mono copy of original ===
appendInfoLine: "Building envelope follower..."

selectObject: original
mono = Convert to mono
Rename: "DynDist_mono"
monoID = selected("Sound")

# === Step 2: Envelope (rectify + low-pass filter) ===
selectObject: monoID
env_temp = Copy: "DynDist_envelope_temp"
Formula: ~ abs(self)

# Low-pass filter to smooth the envelope
envelope = Filter (pass Hann band): 0, response_Speed_Hz, 20
Rename: "DynDist_envelope"
envelopeID = selected("Sound")
removeObject: env_temp

# === Step 3: Apply Dynamic Distortion ===
# v0.3 uses an explicit cross-Sound reference instead of v0.2's
# "stereo container with row-1/row-2 trick." Same math, safer code.
appendInfoLine: "Applying dynamic distortion..."

selectObject: monoID
Copy: origName$ + "_DynDist_" + presetName$
result = selected("Sound")

# Build formula string with object ID reference
envelopeIDStr$ = string$(envelopeID)
b_str$ = string$(base_Drive)
s_str$ = string$(sensitivity)
g_str$ = string$(output_Gain)

selectObject: result
# Formula: tanh(self * (base + envelope * sensitivity)) * output_gain
# Where envelope is read sample-by-sample from the envelope Sound.
Formula: "tanh(self * (" + b_str$ + " + object[" + envelopeIDStr$ + ", col] * " + s_str$ + ")) * " + g_str$

# === Step 4: Normalize ===
selectObject: result
Scale peak: 0.95

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Get envelope range (kept alive for viz; cleaned up after)
selectObject: envelopeID
envMax = Get maximum: 0, 0, "Parabolic"
envMin = Get minimum: 0, 0, "Parabolic"

# Compute drive range from envelope range
driveMax_calc = base_Drive + envMax * sensitivity
driveMin_calc = base_Drive + envMin * sensitivity

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##DYNAMIC DISTORTION (envelope follower)##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... origName$
        ... + "  |  " + presetName$
        ... + "  |  Base: " + fixed$(base_Drive, 2)
        ... + "  |  Sens: " + fixed$(sensitivity, 2)
        ... + "  |  Speed: " + fixed$(response_Speed_Hz, 0) + " Hz"
        ... + "  |  Drive range: " + fixed$(driveMin_calc, 1) + "-" + fixed$(driveMax_calc, 1)
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION WITH DRIVE OVERLAYS  (left, headline)
    # The defining diagnostic for this script.
    # Two tanh curves overlaid: quiet (low drive, gray) vs loud
    # (high drive, red). Shows the touch-sensitive character.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -1.2, 1.2
    
    # Grid + identity reference
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Compute representative drives for "quiet" and "loud" using
    # actual envelope min/max scaled by sensitivity
    driveLow_disp = base_Drive + envMin * sensitivity
    driveHigh_disp = base_Drive + envMax * sensitivity
    
    # For visualization: clamp drives to a visible range, but
    # preserve sign (so GatedCrunch's negative base_Drive shows
    # as inverted curve, which is real behavior, not hidden)
    # Keep the actual computed values, no max() clamping
    
    nPoints = 200
    
    # Low drive curve (quiet sections — gray, behind)
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1.5
    prev_x = -1.0
    prev_y = tanh(prev_x * driveLow_disp) * output_Gain
    if prev_y > 1.15
        prev_y = 1.15
    endif
    if prev_y < -1.15
        prev_y = -1.15
    endif
    for p from 1 to nPoints
        curr_x = -1.0 + (p / nPoints) * 2.0
        curr_y = tanh(curr_x * driveLow_disp) * output_Gain
        if curr_y > 1.15
            curr_y = 1.15
        endif
        if curr_y < -1.15
            curr_y = -1.15
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    
    # High drive curve (loud sections — red, on top)
    Colour: "{0.80, 0.30, 0.30}"
    Line width: 2
    prev_x = -1.0
    prev_y = tanh(prev_x * driveHigh_disp) * output_Gain
    if prev_y > 1.15
        prev_y = 1.15
    endif
    if prev_y < -1.15
        prev_y = -1.15
    endif
    for p from 1 to nPoints
        curr_x = -1.0 + (p / nPoints) * 2.0
        curr_y = tanh(curr_x * driveHigh_disp) * output_Gain
        if curr_y > 1.15
            curr_y = 1.15
        endif
        if curr_y < -1.15
            curr_y = -1.15
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1
    
    # Legend
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    Text: -1.15, "left", 1.10, "half", "gray = quiet (drive " + fixed$(driveLow_disp, 1) + ")"
    Colour: "{0.80, 0.30, 0.30}"
    Text: -1.15, "left", 1.00, "half", "red = loud (drive " + fixed$(driveHigh_disp, 1) + ")"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: ENVELOPE + COMPUTED DRIVE  (right, headline-height)
    # Top half: envelope (rectified + low-passed input)
    # Bottom half: computed drive value at each sample
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    # We split the panel vertically: top 50% = envelope, bottom 50% = drive
    # Use a single Axes call covering [-1, +1] vertically with envelope
    # mapped to [0, 0.5] and drive mapped to [-0.5, -1] approximately.
    # Simpler: use two sequential Select inner viewport calls.
    
    # ---- Sub-panel B1: Envelope (top half) ----
    Select outer viewport: 4.2, 8, 0.75, 2.65
    Select inner viewport: 4.55, 7.75, 0.95, 2.55
    
    selectObject: envelopeID
    envViz_max = envMax * 1.15
    if envViz_max < 0.001
        envViz_max = 0.001
    endif
    
    Axes: 0, duration, 0, envViz_max
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, 0, envViz_max
    
    Colour: "{0.30, 0.65, 0.40}"
    Line width: 1.3
    Draw: 0, 0, 0, envViz_max, "no", "Curve"
    Line width: 1
    
    # Min/max reference lines
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: 0, envMax, duration, envMax
    Draw line: 0, envMin, duration, envMin
    Solid line
    Font size: 5
    Colour: "{0.55, 0.30, 0.55}"
    Text: duration * 0.99, "right", envMax, "bottom", " max " + fixed$(envMax, 3)
    Text: duration * 0.99, "right", envMin, "top", " min " + fixed$(envMin, 3)
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Envelope"
    
    # ---- Sub-panel B2: Computed Drive (bottom half) ----
    Select outer viewport: 4.2, 8, 2.70, 4.60
    Select inner viewport: 4.55, 7.75, 2.85, 4.40
    
    # Compute drive range with padding for display
    drivePad = (driveMax_calc - driveMin_calc) * 0.10
    if drivePad < 0.1
        drivePad = 0.1
    endif
    yLo_drive = driveMin_calc - drivePad
    yHi_drive = driveMax_calc + drivePad
    
    Axes: 0, duration, yLo_drive, yHi_drive
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, yLo_drive, yHi_drive
    
    # Zero line if visible
    if yLo_drive < 0 and yHi_drive > 0
        Colour: "{0.65, 0.65, 0.65}"
        Dotted line
        Draw line: 0, 0, duration, 0
        Solid line
    endif
    
    # base_Drive reference line
    if base_Drive >= yLo_drive and base_Drive <= yHi_drive
        Colour: "{0.78, 0.65, 0.78}"
        Dotted line
        Draw line: 0, base_Drive, duration, base_Drive
        Solid line
        Font size: 5
        Colour: "{0.55, 0.30, 0.55}"
        Text: duration * 0.01, "left", base_Drive, "bottom", " base " + fixed$(base_Drive, 2)
    endif
    
    # Build drive display Sound (in-place from envelope)
    # We compute drive = base + env * sens by copying envelope and applying formula
    selectObject: envelopeID
    driveDisp = Copy: "DynDist_driveDisp_temp"
    Formula: ~ base_Drive + self * sensitivity
    
    Colour: "{0.78, 0.50, 0.30}"
    Line width: 1.3
    Draw: 0, 0, yLo_drive, yHi_drive, "no", "Curve"
    Line width: 1
    
    removeObject: driveDisp
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Drive"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Transfer function (gray=quiet, red=loud)"
    Text: 6.10, "centre", 7.30, "half", "Envelope (upper) & computed drive (lower)"
    
    # ----------------------------------------------------------
    # PANEL C: ORIGINAL VS RESULT (overlay)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    selectObject: original
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    cmpMax = origPeak
    if resPeak > cmpMax
        cmpMax = resPeak
    endif
    if cmpMax < 0.001
        cmpMax = 0.001
    endif
    cAmpViz = cmpMax * 1.15
    
    Axes: 0, duration, -cAmpViz, cAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -cAmpViz, cAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        cOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, duration, -cAmpViz, cAmpViz, "no", "Curve"
        removeObject: cOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, duration, -cAmpViz, cAmpViz, "no", "Curve"
    endif
    
    # Result (red, on top)
    selectObject: result
    Colour: "{0.78, 0.30, 0.30}"
    Line width: 1.3
    Draw: 0, duration, -cAmpViz, cAmpViz, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original (gray) vs Dynamic Distortion (red)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file, mono)
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
    Colour: "{0.20, 0.55, 0.55}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output (mono)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + origName$
        ... + "  |  Base: " + fixed$(base_Drive, 2)
        ... + "  |  Sens: " + fixed$(sensitivity, 2)
        ... + "  |  Speed: " + fixed$(response_Speed_Hz, 1) + " Hz"
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Envelope: " + fixed$(envMin, 3) + "-" + fixed$(envMax, 3)
        ... + "  |  Drive range: " + fixed$(driveMin_calc, 2) + "-" + fixed$(driveMax_calc, 2)
        ... + "  |  Note: input collapsed to mono"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Cleanup ===
removeObject: monoID, envelopeID

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: "Drive range: ", fixed$(driveMin_calc, 2), " - ", fixed$(driveMax_calc, 2)

if play_result
    selectObject: result
    Play
endif

selectObject: result
