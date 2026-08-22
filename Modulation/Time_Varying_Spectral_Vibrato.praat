# ============================================================
# Praat AudioTools - Time_Varying_Spectral_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-Varying PSOLA Vibrato. The vibrato rate and depth evolve
#   linearly over the source duration. Rate is integrated to phase,
#   so accelerating/decelerating presets remain phase-continuous.
#   Each input channel is analysed/resynthesised independently so
#   mono, stereo, and multichannel material keep their channel layout.
#
#   This is a PSOLA/PitchTier effect, not a spectral-analysis effect.
#   The legacy filename is retained for AudioTools compatibility.
#
# Changelog v0.5:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.4:
#   - Visualization-only correction: restored house-style text placement.
#   - Added compact start/end value labels to Rate and Depth panels.
#   - Restored title/subtitle and Summary geometry to the trusted reference.
#
# Changelog v0.3:
#   - Corrected the legacy "spectral" claim: processing is PSOLA/PitchTier.
#   - Fixed absolute-time phase/depth bug by using local source time.
#   - Preserves arbitrary channel counts instead of collapsing to mono.
#   - Allows zero rate/depth values and validates all user parameters.
#   - Added exact Dry/Wet bypass and linear dry/wet mixing.
#   - Removed forced peak normalisation; Safety peak only attenuates.
#   - Added adaptive pitch-analysis bounds for low sample rates.
#   - Updated visualization to AudioTools house style.
# ============================================================

form Time-Varying PSOLA Vibrato v0.5
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Ramp Up (Accelerating)
        option Slow Down (Decelerating)
        option Swell (Fade-In Depth)
        option Fade Out (Dying Wobble)
        option Nervous Shiver (Fast & Shallow)
        option Opera Finale (Wide & Slowing)

    comment === Rate Evolution ===
    real Start_Rate_Hz 4.0
    real End_Rate_Hz 8.0

    comment === Depth Evolution ===
    real Start_Depth_ST 0.1
    real End_Depth_ST 0.1

    comment === Output ===
    real Dry_wet_percent 100
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
selectObject: original
sourceStart = Get start time
sourceEnd = Get end time
duration = Get total duration
samplingRate = Get sampling frequency
numChannels = Get number of channels
inputPeak = Get absolute extremum: 0, 0, "None"

if duration <= 0
    exitScript: "The selected Sound has zero duration."
endif

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    start_Rate_Hz = 2.0
    end_Rate_Hz = 10.0
    start_Depth_ST = 0.2
    end_Depth_ST = 0.2
    presetName$ = "RampUp"
elsif preset = 3
    start_Rate_Hz = 12.0
    end_Rate_Hz = 0.5
    start_Depth_ST = 0.3
    end_Depth_ST = 0.5
    presetName$ = "SlowDown"
elsif preset = 4
    start_Rate_Hz = 5.0
    end_Rate_Hz = 5.0
    start_Depth_ST = 0.0
    end_Depth_ST = 1.0
    presetName$ = "Swell"
elsif preset = 5
    start_Rate_Hz = 6.0
    end_Rate_Hz = 3.0
    start_Depth_ST = 0.5
    end_Depth_ST = 0.0
    presetName$ = "FadeOut"
elsif preset = 6
    start_Rate_Hz = 8.0
    end_Rate_Hz = 12.0
    start_Depth_ST = 0.1
    end_Depth_ST = 0.1
    presetName$ = "Shiver"
elsif preset = 7
    start_Rate_Hz = 5.5
    end_Rate_Hz = 4.0
    start_Depth_ST = 0.3
    end_Depth_ST = 1.5
    presetName$ = "Opera"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION
# ============================================================
if start_Rate_Hz < 0
    start_Rate_Hz = 0
endif
if end_Rate_Hz < 0
    end_Rate_Hz = 0
endif
if start_Rate_Hz > 50
    start_Rate_Hz = 50
endif
if end_Rate_Hz > 50
    end_Rate_Hz = 50
endif
if start_Depth_ST < 0
    start_Depth_ST = 0
endif
if end_Depth_ST < 0
    end_Depth_ST = 0
endif
if start_Depth_ST > 24
    start_Depth_ST = 24
endif
if end_Depth_ST > 24
    end_Depth_ST = 24
endif
if dry_wet_percent < 0
    dry_wet_percent = 0
endif
if dry_wet_percent > 100
    dry_wet_percent = 100
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

rateSlope = (end_Rate_Hz - start_Rate_Hz) / duration
depthSlope = (end_Depth_ST - start_Depth_ST) / duration

# Pitch bounds used by Manipulation. Keep the ceiling below Nyquist at low Fs.
pitchFloor = 75
pitchCeiling = min(600, 0.40 * samplingRate)
if pitchCeiling <= pitchFloor * 1.5
    pitchFloor = max(20, pitchCeiling / 3)
endif

# ============================================================
# INFO
# ============================================================
clearinfo
writeInfoLine: "=== Time-Varying PSOLA Vibrato v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(samplingRate, 0), " Hz"
appendInfoLine: "Rate: ", fixed$(start_Rate_Hz, 3), " -> ", fixed$(end_Rate_Hz, 3), " Hz"
appendInfoLine: "Depth: ", fixed$(start_Depth_ST, 3), " -> ", fixed$(end_Depth_ST, 3), " st"
appendInfoLine: "Pitch analysis: ", fixed$(pitchFloor, 1), " - ", fixed$(pitchCeiling, 1), " Hz"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
appendInfoLine: "Algorithm: per-channel PSOLA / PitchTier (legacy filename says spectral)"
appendInfoLine: ""

# Exact bypass: no processing, no safety alteration.
if dry_wet_percent = 0 or (start_Depth_ST = 0 and end_Depth_ST = 0)
    selectObject: original
    result = Copy: originalName$ + "_timeVib_" + presetName$
    bypassed = 1
else
    bypassed = 0
    processedIDs# = zero#(numChannels)

    for ch from 1 to numChannels
        selectObject: original
        if numChannels = 1
            channelIn = Copy: "tvv_channel"
        else
            Extract one channel: ch
            channelIn = selected("Sound")
        endif

        @processChannel: channelIn
        processedIDs#[ch] = channelOut_result
        removeObject: channelIn
    endfor

    if numChannels = 1
        result = processedIDs#[1]
        selectObject: result
        Rename: originalName$ + "_timeVib_" + presetName$
    else
        selectObject: processedIDs#[1]
        for ch from 2 to numChannels
            plusObject: processedIDs#[ch]
        endfor
        Combine to stereo
        result = selected("Sound")
        Rename: originalName$ + "_timeVib_" + presetName$
        for ch from 1 to numChannels
            removeObject: processedIDs#[ch]
        endfor
    endif

    if dry_wet_percent < 100
        wetMix = dry_wet_percent / 100
        dryMix = 1 - wetMix
        selectObject: result
        Formula: "'wetMix' * self + 'dryMix' * object ['original', row, col]"
    endif
endif

# ============================================================
# SAFETY (attenuation only; disabled with 0)
# ============================================================
selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if not bypassed and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)
if bypassed
    appendInfoLine: "Bypass: exact"
elsif safety_peak = 0
    appendInfoLine: "Safety: disabled"
else
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
endif
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    pageHeight = 5.5
    Erase all

    # Title / subtitle
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Time-Varying PSOLA Vibrato v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", "Time_Varying_Spectral_Vibrato.praat  |  " + presetName$ + "  |  PSOLA/PitchTier"

    # Input
    Select outer viewport: 0, 4, 0.65, 1.75
    Select inner viewport: 0.55, 3.75, 0.78, 1.62
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output
    Select outer viewport: 4, 8, 0.65, 1.75
    Select inner viewport: 4.35, 7.55, 0.78, 1.62
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # Rate evolution
    Select outer viewport: 0, 4, 1.9, 3.0
    Select inner viewport: 0.55, 3.75, 2.03, 2.87
    minRate = min(start_Rate_Hz, end_Rate_Hz)
    maxRate = max(start_Rate_Hz, end_Rate_Hz)
    padRate = max(0.2, 0.10 * max(1, maxRate - minRate))
    Axes: 0, duration, max(0, minRate-padRate), maxRate+padRate
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, max(0, minRate-padRate), maxRate+padRate
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    Draw line: 0, start_Rate_Hz, duration, end_Rate_Hz
    Line width: 1
    Font size: 6
    Colour: "{0.48, 0.35, 0.74}"
    Text: duration * 0.02, "left", start_Rate_Hz, "half", fixed$(start_Rate_Hz, 2) + " Hz"
    Text: duration * 0.98, "right", end_Rate_Hz, "half", fixed$(end_Rate_Hz, 2) + " Hz"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Rate (Hz)"
    Text bottom: "yes", "Time (s)"

    # Depth evolution
    Select outer viewport: 4, 8, 1.9, 3.0
    Select inner viewport: 4.35, 7.55, 2.03, 2.87
    maxDepth = max(start_Depth_ST, end_Depth_ST)
    depthTop = max(0.2, maxDepth * 1.15)
    Axes: 0, duration, 0, depthTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, depthTop
    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1.5
    Draw line: 0, start_Depth_ST, duration, end_Depth_ST
    Line width: 1
    Font size: 6
    Colour: "{0.22, 0.46, 0.82}"
    Text: duration * 0.02, "left", start_Depth_ST, "half", fixed$(start_Depth_ST, 2) + " st"
    Text: duration * 0.98, "right", end_Depth_ST, "half", fixed$(end_Depth_ST, 2) + " st"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Depth (st)"
    Text bottom: "yes", "Time (s)"

    # Actual pitch-deviation trajectory
    Select outer viewport: 0, 8, 3.15, 4.45
    Select inner viewport: 0.55, 7.55, 3.28, 4.30
    maxDev = max(0.2, maxDepth * 1.10)
    Axes: 0, duration, -maxDev, maxDev
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -maxDev, maxDev
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.25
    nViz = 500
    for p from 2 to nViz
        t1 = (p-2)/(nViz-1) * duration
        t2 = (p-1)/(nViz-1) * duration
        d1 = start_Depth_ST + depthSlope*t1
        d2 = start_Depth_ST + depthSlope*t2
        ph1 = 2*pi*(start_Rate_Hz*t1 + 0.5*rateSlope*t1^2)
        ph2 = 2*pi*(start_Rate_Hz*t2 + 0.5*rateSlope*t2^2)
        dev1 = d1 * sin(ph1)
        dev2 = d2 * sin(ph2)
        Draw line: t1, dev1, t2, dev2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pitch deviation (st)"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 4.60, 5.35
    Select inner viewport: 0.6, 7.7, 4.65, 5.30
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", "Rate " + fixed$(start_Rate_Hz, 2) + "->" + fixed$(end_Rate_Hz, 2) + " Hz  |  Depth " + fixed$(start_Depth_ST, 2) + "->" + fixed$(end_Depth_ST, 2) + " st  |  Wet " + fixed$(dry_wet_percent, 0) + "%"
    Text: 0.02, "left", 0.18, "half", "Duration " + fixed$(duration, 2) + " s  |  Channels " + string$(numChannels) + "  |  Peak " + fixed$(outputPeak, 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

selectObject: result
if play_result
    Play
endif
selectObject: result

# ============================================================
# PROCESS ONE MONO CHANNEL
# ============================================================
procedure processChannel: .inputID
    selectObject: .inputID
    To Manipulation: 0.01, pitchFloor, pitchCeiling
    .manipID = selected("Manipulation")

    Extract pitch tier
    .tierID = selected("PitchTier")

    selectObject: .tierID
    Formula: "self * 2 ^ ((start_Depth_ST + depthSlope * (x - sourceStart)) * sin(2*pi * (start_Rate_Hz * (x - sourceStart) + 0.5 * rateSlope * (x - sourceStart)^2)) / 12)"

    selectObject: .manipID
    plusObject: .tierID
    Replace pitch tier

    selectObject: .manipID
    Get resynthesis (overlap-add)
    channelOut_result = selected("Sound")

    removeObject: .manipID, .tierID
endproc
