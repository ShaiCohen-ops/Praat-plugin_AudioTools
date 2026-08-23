# ============================================================
# Praat AudioTools - Stereo_Delay_Splitter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Delay Splitter - per channel, applies an FIR high-pass comb
#   (y[n] = x[n+D] - x[n], zero at DC) with different delays on L and R
#   to create stereo width / spectral separation.
#   Delay_mode selects how D is set:
#     Divisor      - D = totalSamples/divisor (fraction of file). Notch
#                    spacing is only divisor/duration Hz, so perceptually
#                    broadband decorrelation/widening, not tonal comb, and
#                    the forward read leaves the last 1/divisor dry.
#     Milliseconds - fixed short delays for audible tonal comb filtering.
#     Tempo-synced - delays set as note values (1/2..1/32, incl. dotted)
#                    at Manual_bpm; D = beats * (60/bpm) * sampleRate.
#
# Changelog v0.6:
#   - API COMPATIBILITY: public form is byte-for-byte unchanged from v0.5.
#     Output name remains <source>_stereo_split.
#   - ROBUSTNESS: mono->stereo preparation now tracks temporary Sounds by ID
#     rather than by generic names (left_tmp/right_tmp), preventing collisions
#     with pre-existing objects in caller scripts.
#   - SAFE NORMALIZATION: Scale peak is skipped for digital silence.
#   - MULTICHANNEL: inputs with >2 channels still intentionally produce stereo
#     from channels 1/2, but this is now reported explicitly in the Info window.
#   - VISUALIZATION: spectrum upper bound is capped at Nyquist instead of a
#     hard-coded 5 kHz; title panel resets normalized axes explicitly.
#
# Changelog v0.5:
#   - Added Wet_dry mix (0 = dry, 1 = fully wet). Each channel is mixed
#     against its pre-processing dry copy. Default 1.0 reproduces v0.4.
#
# Changelog v0.4:
#   - Added Tempo-synced delay mode: per-channel note values at a manual
#     BPM (1/2, 1/4, 1/4., 1/8, 1/8., 1/16, 1/16., 1/32). Delay_mode is
#     now a 3-way selector (Divisor / Milliseconds / Tempo-synced),
#     replacing the Use_ms_delay boolean.
#   - Info warns if a delay >= file length (that pass leaves the channel dry).
#
# Changelog v0.3:
#   - Added optional millisecond-delay mode (Use_ms_delay, off by default)
#     for true audible comb filtering; divisor mode unchanged when off.
#   - Delays clamped to >=1 sample (a 0-sample delay would null the channel).
#   - Viz fix: spectra are now computed on a mono fold (To Spectrum is
#     mono-only; result is always stereo, so the panel crashed every run).
#   - Viz fix: divisor/delay info text was placed in inherited spectrum
#     axes (clamped off-panel); now drawn in normalized axes.
#   - Description corrected to describe the actual effect.
# ============================================================

form Stereo Delay Splitter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (L:2,4 | R:8,10)
        option Narrow Stereo (L:3,5 | R:6,8)
        option Wide Stereo (L:2,6 | R:12,18)
        option Alt Divisors (L:2,3 | R:9,15)
        option Custom
    
    comment === Left Channel Divisors ===
    positive Divisor_L1 2
    positive Divisor_L2 4
    
    comment === Right Channel Divisors ===
    positive Divisor_R1 8
    positive Divisor_R2 10
    
    comment === Delay Mode ===
    optionmenu Delay_mode 1
        option Divisor (fraction of file)
        option Milliseconds
        option Tempo-synced (BPM)
    
    comment === Millisecond Delays (Milliseconds mode) ===
    positive Delay_L1_ms 3
    positive Delay_L2_ms 5
    positive Delay_R1_ms 7
    positive Delay_R2_ms 11
    
    comment === Tempo (Tempo-synced mode) ===
    positive Manual_bpm 120
    optionmenu Note_L1 4
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    optionmenu Note_L2 6
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    optionmenu Note_R1 2
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    optionmenu Note_R2 5
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    
    comment === Mix ===
    real Wet_dry 1.0
    
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default
    divisor_L1 = 2
    divisor_L2 = 4
    divisor_R1 = 8
    divisor_R2 = 10
elsif preset = 2
    # Narrow Stereo
    divisor_L1 = 3
    divisor_L2 = 5
    divisor_R1 = 6
    divisor_R2 = 8
elsif preset = 3
    # Wide Stereo
    divisor_L1 = 2
    divisor_L2 = 6
    divisor_R1 = 12
    divisor_R2 = 18
elsif preset = 4
    # Alt Divisors
    divisor_L1 = 2
    divisor_L2 = 3
    divisor_R1 = 9
    divisor_R2 = 15
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")
display_name$ = replace$(original_name$, "_", " ", 0)

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples
numChannels = Get number of channels

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Narrow"
elsif preset = 3
    presetName$ = "Wide"
elsif preset = 4
    presetName$ = "Alt"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Stereo Delay Splitter ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Left divisors: ", divisor_L1, ", ", divisor_L2
appendInfoLine: "Right divisors: ", divisor_R1, ", ", divisor_R2
appendInfoLine: ""

# === Prepare Source ===
if numChannels = 1
    selectObject: original
    Copy: "left_tmp"
    leftTmpID = selected("Sound")
    selectObject: original
    Copy: "right_tmp"
    rightTmpID = selected("Sound")

    # Use object IDs, not generic names: caller scripts may already contain
    # objects called left_tmp/right_tmp. Copies are created L then R, so their
    # Object-list order also preserves the intended stereo channel order.
    selectObject: leftTmpID, rightTmpID
    Combine to stereo
    sourceSound = selected("Sound")
    removeObject: leftTmpID, rightTmpID
    appendInfoLine: "Converted mono to stereo for processing"
else
    selectObject: original
    Copy: "stereo_temp"
    sourceSound = selected("Sound")
    if numChannels > 2
        appendInfoLine: "Input has ", numChannels, " channels; using channels 1 and 2 for stereo output"
    endif
endif

# === Calculate Delays ===
if delay_mode = 2
    # Milliseconds
    delayL1 = round(delay_L1_ms / 1000 * sampleRate)
    delayL2 = round(delay_L2_ms / 1000 * sampleRate)
    delayR1 = round(delay_R1_ms / 1000 * sampleRate)
    delayR2 = round(delay_R2_ms / 1000 * sampleRate)
elsif delay_mode = 3
    # Tempo-synced: beats = multiple of the quarter-note (the beat)
    # note option -> beats: 1/2, 1/4, 1/4., 1/8, 1/8., 1/16, 1/16., 1/32
    beatsTable# = {2, 1, 1.5, 0.5, 0.75, 0.25, 0.375, 0.125}
    beat = 60 / manual_bpm
    delayL1 = round(beatsTable#[note_L1] * beat * sampleRate)
    delayL2 = round(beatsTable#[note_L2] * beat * sampleRate)
    delayR1 = round(beatsTable#[note_R1] * beat * sampleRate)
    delayR2 = round(beatsTable#[note_R2] * beat * sampleRate)
else
    # Divisor (fraction of file)
    delayL1 = round(totalSamples / divisor_L1)
    delayL2 = round(totalSamples / divisor_L2)
    delayR1 = round(totalSamples / divisor_R1)
    delayR2 = round(totalSamples / divisor_R2)
endif

# Clamp to >=1 sample (a 0-sample delay would null the channel)
if delayL1 < 1
    delayL1 = 1
endif
if delayL2 < 1
    delayL2 = 1
endif
if delayR1 < 1
    delayR1 = 1
endif
if delayR2 < 1
    delayR2 = 1
endif

if delay_mode = 2
    delayLabel$ = "L: " + fixed$(delay_L1_ms, 1) + ", " + fixed$(delay_L2_ms, 1) + " ms | R: " + fixed$(delay_R1_ms, 1) + ", " + fixed$(delay_R2_ms, 1) + " ms | FIR high-pass comb"
    appendInfoLine: "Delay mode: millisecond (comb filtering)"
elsif delay_mode = 3
    @noteName: note_L1
    nL1$ = noteName$
    @noteName: note_L2
    nL2$ = noteName$
    @noteName: note_R1
    nR1$ = noteName$
    @noteName: note_R2
    nR2$ = noteName$
    delayLabel$ = "Tempo " + string$(manual_bpm) + " BPM | L: " + nL1$ + ", " + nL2$ + " | R: " + nR1$ + ", " + nR2$ + " | FIR high-pass comb"
    appendInfoLine: "Delay mode: tempo-synced (", manual_bpm, " BPM)"
else
    delayLabel$ = "L: " + string$(divisor_L1) + ", " + string$(divisor_L2) + " | R: " + string$(divisor_R1) + ", " + string$(divisor_R2) + " (divisors) | dense comb -> decorrelation/widening"
    appendInfoLine: "Delay mode: divisor (fraction of file)"
endif

# Warn if any delay reaches the file length (that channel iteration is a no-op)
if delayL1 >= totalSamples or delayL2 >= totalSamples or delayR1 >= totalSamples or delayR2 >= totalSamples
    appendInfoLine: "WARNING: a delay >= file length; that pass leaves the channel dry"
endif

appendInfoLine: "Left delays: ", delayL1, ", ", delayL2, " samples"
appendInfoLine: "Right delays: ", delayR1, ", ", delayR2, " samples"

# Wet/dry clamp to [0,1]
if wet_dry < 0
    wet_dry = 0
endif
if wet_dry > 1
    wet_dry = 1
endif
appendInfoLine: "Wet/dry: ", fixed$(wet_dry, 2)
appendInfoLine: ""

# === Process Left Channel ===
selectObject: sourceSound
Extract one channel: 1
leftDry = selected("Sound")
Rename: "LeftDry"
Copy: "Left"
leftChannel = selected("Sound")

appendInfoLine: "Processing left channel..."

# Iteration 1
selectObject: leftChannel
Formula: ~ if col + delayL1 <= ncol then self[col + delayL1] - self else self fi

# Iteration 2
Formula: ~ if col + delayL2 <= ncol then self[col + delayL2] - self else self fi

# Wet/dry mix against the dry channel
selectObject: leftChannel
Formula: ~ self * wet_dry + object[leftDry, row, col] * (1 - wet_dry)

# === Process Right Channel ===
selectObject: sourceSound
Extract one channel: 2
rightDry = selected("Sound")
Rename: "RightDry"
Copy: "Right"
rightChannel = selected("Sound")

appendInfoLine: "Processing right channel..."

# Iteration 1
selectObject: rightChannel
Formula: ~ if col + delayR1 <= ncol then self[col + delayR1] - self else self fi

# Iteration 2
Formula: ~ if col + delayR2 <= ncol then self[col + delayR2] - self else self fi

# Wet/dry mix against the dry channel
selectObject: rightChannel
Formula: ~ self * wet_dry + object[rightDry, row, col] * (1 - wet_dry)

# === Combine to Stereo ===
selectObject: leftChannel, rightChannel
Combine to stereo
result = selected("Sound")
Rename: original_name$ + "_stereo_split"

# Keep the existing normalization contract, but avoid scaling digital silence.
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: scale_peak
endif

# === Cleanup ===
removeObject: leftChannel, rightChannel, leftDry, rightDry, sourceSound

# === Visualization ===
if draw_visualization
    Erase all

    # Shared waveform amplitude scale for truthful Source/Result comparison
    selectObject: original
    originalPeakViz = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: result
    resultPeakViz = Get absolute extremum: 0, 0, "Sinc70"
    vizAmp = max(originalPeakViz, resultPeakViz)
    if vizAmp <= 0
        vizAmp = 1
    endif
    vizAmp = 1.05 * vizAmp

    # Values used by the stereo delay geometry graph
    delayL1msViz = 1000 * delayL1 / sampleRate
    delayL2msViz = 1000 * delayL2 / sampleRate
    delayR1msViz = 1000 * delayR1 / sampleRate
    delayR2msViz = 1000 * delayR2 / sampleRate
    sumLmsViz = delayL1msViz + delayL2msViz
    sumRmsViz = delayR1msViz + delayR2msViz
    maxTapMsViz = max(sumLmsViz, sumRmsViz)
    if maxTapMsViz <= 0
        maxTapMsViz = 1
    endif
    dryViz = 1 - wet_dry

    # Title
    Select outer viewport: 1, 8, 0.08, 0.42
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Delay Splitter: " + display_name$ + " (" + presetName$ + ")"

    # Source waveform: context only
    Select outer viewport: 0, 8, 0.50, 1.45
    Select inner viewport: 0.6, 7.6, 0.60, 1.36
    selectObject: original
    Colour: "{0.62, 0.62, 0.62}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0.08, 0.50, 0.60, 1.36
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "half", "Times", 8, "90", "Source"

    # ========================================================
    # Stereo delay geometry - a visual graph of the process
    # ========================================================
    Select outer viewport: 0.30, 7.80, 1.20, 3.70
    Axes: 0, 1, 0, 1

    # Panel background and frame
    Paint rectangle: "{0.975, 0.975, 0.980}", 0, 1, 0, 1
    Colour: "{0.72, 0.72, 0.74}"
    Draw rectangle: 0, 1, 0, 1

    # Panel title
    Colour: "Black"
    Font size: 9.5
    Text: 0.5, "centre", 0.980, "half", "Stereo delay geometry"
    Font size: 6.3
    Colour: "{0.38, 0.38, 0.42}"
    Text: 0.5, "centre", 0.845, "half", "same source -> different L/R tap spacing   |   wet " + fixed$(100 * wet_dry, 0) + "% / dry " + fixed$(100 * dryViz, 0) + "%"

    # Normalized geometry
    sourceX = 0.085
    splitX = 0.165
    laneStart = 0.255
    laneEnd = 0.930
    laneWidth = laneEnd - laneStart
    yL = 0.650
    yR = 0.345

    # Map the actual delays to one shared horizontal time axis
    xL1 = laneStart + laneWidth * delayL1msViz / maxTapMsViz
    xL2 = laneStart + laneWidth * delayL2msViz / maxTapMsViz
    xLsum = laneStart + laneWidth * sumLmsViz / maxTapMsViz
    xR1 = laneStart + laneWidth * delayR1msViz / maxTapMsViz
    xR2 = laneStart + laneWidth * delayR2msViz / maxTapMsViz
    xRsum = laneStart + laneWidth * sumRmsViz / maxTapMsViz

    # Source node and stereo split
    Paint circle (mm): "{0.58, 0.58, 0.62}", sourceX, 0.5, 2.5
    Colour: "{0.42, 0.42, 0.46}"
    Line width: 1.2
    Draw line: sourceX + 0.012, 0.5, splitX, 0.5
    Draw line: splitX, 0.5, laneStart, yL
    Draw line: splitX, 0.5, laneStart, yR
    Paint circle (mm): "{0.42, 0.42, 0.46}", splitX, 0.5, 1.15
    Line width: 1

    Font size: 6.5
    Colour: "{0.32, 0.32, 0.35}"
    Text: sourceX, "centre", 0.585, "half", "SOURCE"

    # Shared delay axis and lane baselines
    Colour: "{0.76, 0.76, 0.79}"
    Draw line: laneStart, 0.235, laneEnd, 0.235
    Draw line: laneStart, yL, laneEnd, yL
    Draw line: laneStart, yR, laneEnd, yR

    # Axis ticks: 0, 25, 50, 75, 100 percent of the largest tap delay
    Font size: 5.8
    for tick from 0 to 4
        frac = tick / 4
        xt = laneStart + laneWidth * frac
        Colour: "{0.78, 0.78, 0.80}"
        Draw line: xt, 0.220, xt, 0.250
        Colour: "{0.40, 0.40, 0.43}"
        Text: xt, "centre", 0.185, "half", fixed$(maxTapMsViz * frac, 1) + " ms"
    endfor
    Font size: 6.0
    Text: 0.592, "centre", 0.125, "half", "relative delay"

    # Lane labels
    Font size: 8.5
    Colour: "{0.22, 0.43, 0.68}"
    Text: 0.220, "centre", yL, "half", "L"
    Colour: "{0.72, 0.38, 0.28}"
    Text: 0.220, "centre", yR, "half", "R"

    # Marker size: the delayed taps visually shrink with wet amount,
    # while the zero-delay tap remains the stable source anchor.
    delayedRadius = 1.45 + 1.10 * wet_dry
    zeroRadius = 2.55

    # L: + at 0, - at D1, - at D2, + at D1+D2
    Paint circle (mm): "{0.22, 0.43, 0.68}", laneStart, yL, zeroRadius
    Paint circle (mm): "White", xL1, yL, delayedRadius
    Colour: "{0.22, 0.43, 0.68}"
    Draw circle (mm): xL1, yL, delayedRadius
    Paint circle (mm): "White", xL2, yL, delayedRadius
    Draw circle (mm): xL2, yL, delayedRadius
    Paint circle (mm): "{0.22, 0.43, 0.68}", xLsum, yL, delayedRadius

    # R: same tap signs, different spacing
    Paint circle (mm): "{0.72, 0.38, 0.28}", laneStart, yR, zeroRadius
    Paint circle (mm): "White", xR1, yR, delayedRadius
    Colour: "{0.72, 0.38, 0.28}"
    Draw circle (mm): xR1, yR, delayedRadius
    Paint circle (mm): "White", xR2, yR, delayedRadius
    Draw circle (mm): xR2, yR, delayedRadius
    Paint circle (mm): "{0.72, 0.38, 0.28}", xRsum, yR, delayedRadius

    # Delay labels sit close to the taps rather than in explanatory boxes
    Font size: 5.7
    Colour: "{0.22, 0.43, 0.68}"
    Text: xL1, "centre", yL + 0.075, "half", "D1 " + fixed$(delayL1msViz, 1)
    Text: xL2, "centre", yL - 0.075, "half", "D2 " + fixed$(delayL2msViz, 1)
    Text: xLsum, "centre", yL + 0.075, "half", "sum " + fixed$(sumLmsViz, 1)
    Colour: "{0.72, 0.38, 0.28}"
    Text: xR1, "centre", yR + 0.075, "half", "D1 " + fixed$(delayR1msViz, 1)
    Text: xR2, "centre", yR - 0.075, "half", "D2 " + fixed$(delayR2msViz, 1)
    Text: xRsum, "centre", yR + 0.075, "half", "sum " + fixed$(sumRmsViz, 1)

    # Compact visual legend: no equations
    Font size: 6.0
    Paint circle (mm): "{0.50, 0.50, 0.54}", 0.315, 0.075, 1.25
    Colour: "{0.38, 0.38, 0.42}"
    Text: 0.335, "left", 0.075, "half", "filled = positive tap"
    Paint circle (mm): "White", 0.590, 0.075, 1.25
    Colour: "{0.50, 0.50, 0.54}"
    Draw circle (mm): 0.590, 0.075, 1.25
    Colour: "{0.38, 0.38, 0.42}"
    Text: 0.610, "left", 0.075, "half", "ring = negative tap"

    # Result waveform: consequence of the process
    Select outer viewport: 0, 8, 3.82, 4.68
    Select inner viewport: 0.6, 7.6, 3.90, 4.59
    selectObject: result
    Colour: "{0.50, 0.60, 0.70}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0.08, 0.50, 3.90, 4.59
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "half", "Times", 8, "90", "Stereo result"

    # Spectrum display range: never request frequencies above Nyquist.
    vizMaxHz = min(5000, sampleRate / 2)

    # Original spectrum
    Select outer viewport: 0, 4, 4.88, 6.18
    Select inner viewport: 0.6, 3.8, 5.00, 6.07
    selectObject: original
    nch = Get number of channels
    if nch > 1
        specMono = Convert to mono
    else
        specMono = Copy: "specMono"
    endif
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Colour: "{0.62, 0.62, 0.62}"
    Draw: 0, vizMaxHz, 0, 80, "no"
    removeObject: origSpec, specMono
    Colour: "Black"
    Draw inner box
    Font size: 6.5
    Text left: "yes", "dB"
    Text bottom: "yes", "Original spectrum (Hz)"

    # Result spectrum (shows comb filtering)
    Select outer viewport: 4, 8, 4.88, 6.18
    Select inner viewport: 4.4, 7.6, 5.00, 6.07
    selectObject: result
    resMono = Convert to mono
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    Colour: "{0.50, 0.60, 0.70}"
    Draw: 0, vizMaxHz, 0, 80, "no"
    removeObject: resSpec, resMono
    Colour: "Black"
    Draw inner box
    Font size: 6.5
    Text left: "yes", "dB"
    Text bottom: "yes", "Split spectrum (Hz)"

    # Summary strip
    Select outer viewport: 0.45, 7.55, 6.42, 6.86
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.965, 0.965, 0.972}", 0, 1, 0, 1
    Colour: "{0.78, 0.78, 0.80}"
    Draw rectangle: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.34}"
    Font size: 6.4
    Text: 0.5, "centre", 0.5, "half", "Summary  |  L " + fixed$(delayL1msViz, 1) + " / " + fixed$(delayL2msViz, 1) + " ms  |  R " + fixed$(delayR1msViz, 1) + " / " + fixed$(delayR2msViz, 1) + " ms  |  wet " + fixed$(100 * wet_dry, 0) + "% / dry " + fixed$(100 * dryViz, 0) + "%"

    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result

procedure noteName: .opt
    if .opt = 1
        noteName$ = "1/2"
    elsif .opt = 2
        noteName$ = "1/4"
    elsif .opt = 3
        noteName$ = "1/4."
    elsif .opt = 4
        noteName$ = "1/8"
    elsif .opt = 5
        noteName$ = "1/8."
    elsif .opt = 6
        noteName$ = "1/16"
    elsif .opt = 7
        noteName$ = "1/16."
    else
        noteName$ = "1/32"
    endif
endproc