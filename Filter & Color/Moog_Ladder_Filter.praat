# ============================================================
# Praat AudioTools - Moog_Ladder_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Description:
#   Moog-style 4-pole resonant lowpass based on the linearized
#   topology-preserving-transform (TPT) ladder transfer function.
#   The four trapezoidal one-pole stages are closed by a zero-delay
#   feedback loop and evaluated as the equivalent 4th-order IIR.
#
#   Static mode is the exact linear transfer of this digital ladder.
#   Automation uses smoothly time-varying IIR coefficients (no chunk
#   resets), which preserves state continuously during sweeps.
#
#   The optional output saturation is POST-filter saturation only;
#   this is not a transistor-level nonlinear Moog circuit emulation.
#   The asymptotic lowpass slope is 24 dB/octave.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Moog-Style TPT Ladder Filter v0.5
    optionmenu Preset: 1
        option Custom
        option Bass Filter (300 Hz, res 0.3)
        option Warm Pad (800 Hz, res 0.5)
        option Vocal Resonance (1500 Hz, res 0.65)
        option Bright Lowpass (2500 Hz, res 0.55)
        option Resonant Peak (1200 Hz, res 0.75)
        option Telephone-Style Lowpass (2800 Hz, res 0.35)
        option Sub Bass (150 Hz, res 0.2)
        option Acid Bass (500 Hz, res 0.75)
        option Cutoff Sweep Up (200-3000 Hz)
        option Cutoff Sweep Down (3000-200 Hz)
        option Resonance Sweep (res 0.1-0.85)
    comment === Static Parameters ===
    positive Cutoff_frequency 1000
    real Resonance 0.7
    comment (0-0.99; mapped to feedback k=4*resonance^1.5)
    comment === Automation Parameters ===
    positive Start_cutoff 200
    positive End_cutoff 3000
    real Start_resonance 0.2
    real End_resonance 0.8
    comment === Output ===
    boolean DC_blocker 1
    optionmenu Limiter_type: 2
        option Off (linear)
        option Soft (x/(1+|x|))
        option Tanh
    real Output_trim_dB 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
use_automation = 0

if preset = 2
    cutoff_frequency = 300
    resonance = 0.3
    presetName$ = "BassFilter"
elsif preset = 3
    cutoff_frequency = 800
    resonance = 0.5
    presetName$ = "WarmPad"
elsif preset = 4
    cutoff_frequency = 1500
    resonance = 0.65
    presetName$ = "VocalResonance"
elsif preset = 5
    cutoff_frequency = 2500
    resonance = 0.55
    presetName$ = "BrightLowpass"
elsif preset = 6
    cutoff_frequency = 1200
    resonance = 0.75
    presetName$ = "ResonantPeak"
elsif preset = 7
    cutoff_frequency = 2800
    resonance = 0.35
    presetName$ = "TelephoneLowpass"
elsif preset = 8
    cutoff_frequency = 150
    resonance = 0.2
    presetName$ = "SubBass"
elsif preset = 9
    cutoff_frequency = 500
    resonance = 0.75
    presetName$ = "AcidBass"
elsif preset = 10
    start_cutoff = 200
    end_cutoff = 3000
    start_resonance = 0.5
    end_resonance = 0.5
    use_automation = 1
    presetName$ = "SweepUp"
elsif preset = 11
    start_cutoff = 3000
    end_cutoff = 200
    start_resonance = 0.5
    end_resonance = 0.5
    use_automation = 1
    presetName$ = "SweepDown"
elsif preset = 12
    start_cutoff = 800
    end_cutoff = 800
    start_resonance = 0.1
    end_resonance = 0.85
    use_automation = 1
    presetName$ = "ResSweep"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP + PARAMETER CLAMPS
# ============================================================
selectObject: soundID
samplingFrequency = Get sampling frequency
duration = Get total duration
numberOfChannels = Get number of channels
numberOfSamples = Get number of samples
xmin0 = Get start time
nyquist = samplingFrequency / 2

if numberOfSamples < 8
    exitScript: "Sound is too short (need at least 8 samples)."
endif

# Keep the bilinear prewarp safely below Nyquist.
minCut = 5
maxCut = 0.45 * samplingFrequency
if maxCut > nyquist - 5
    maxCut = nyquist - 5
endif
if maxCut < minCut
    exitScript: "Sample rate is too low for this filter."
endif

if cutoff_frequency < minCut
    cutoff_frequency = minCut
elsif cutoff_frequency > maxCut
    cutoff_frequency = maxCut
endif
if start_cutoff < minCut
    start_cutoff = minCut
elsif start_cutoff > maxCut
    start_cutoff = maxCut
endif
if end_cutoff < minCut
    end_cutoff = minCut
elsif end_cutoff > maxCut
    end_cutoff = maxCut
endif

if resonance < 0
    resonance = 0
elsif resonance > 0.99
    resonance = 0.99
endif
if start_resonance < 0
    start_resonance = 0
elsif start_resonance > 0.99
    start_resonance = 0.99
endif
if end_resonance < 0
    end_resonance = 0
elsif end_resonance > 0.99
    end_resonance = 0.99
endif

if output_trim_dB < -60
    output_trim_dB = -60
elsif output_trim_dB > 24
    output_trim_dB = 24
endif
trimGain = 10 ^ (output_trim_dB / 20)

# ============================================================
# REPORT HEADER
# ============================================================
clearinfo
writeInfoLine: "=== Moog-Style TPT Ladder Filter v0.5 ==="
appendInfoLine: "Input: ", soundName$, "  |  ", fixed$(duration, 3), " s  |  ", numberOfChannels, " ch"
appendInfoLine: "Sample rate: ", fixed$(samplingFrequency, 0), " Hz"
appendInfoLine: "Preset: ", presetName$
if use_automation
    appendInfoLine: "Mode: continuous automation"
    appendInfoLine: "Pole cutoff: ", fixed$(start_cutoff, 1), " -> ", fixed$(end_cutoff, 1), " Hz"
    appendInfoLine: "Resonance: ", fixed$(start_resonance, 3), " -> ", fixed$(end_resonance, 3)
else
    appendInfoLine: "Mode: static"
    appendInfoLine: "Pole cutoff: ", fixed$(cutoff_frequency, 1), " Hz"
    appendInfoLine: "Resonance: ", fixed$(resonance, 3)
endif
if limiter_type = 1
    limiterName$ = "Off (linear)"
elsif limiter_type = 2
    limiterName$ = "Soft x/(1+|x|)"
else
    limiterName$ = "Tanh"
endif
appendInfoLine: "Output saturation: ", limiterName$
appendInfoLine: "Output trim: ", fixed$(output_trim_dB, 1), " dB"
appendInfoLine: ""

# ============================================================
# LINEARIZED TPT LADDER CORE
#
# One trapezoidal one-pole stage:
#   H1(z) = G (1 + z^-1) / (1 - R z^-1)
# where g=tan(pi*fc/fs), G=g/(1+g), R=(1-g)/(1+g).
# Four stages with feedback k give:
#   H(z) = B(z)^4 / (A(z)^4 + k B(z)^4)
# This removes the zero-delay algebraic loop exactly in the linear model.
# ============================================================

selectObject: soundID
resultID = Copy: soundName$ + "_moog_" + presetName$
soundId$ = string$(soundID)

if use_automation = 0
    g = tan(pi * cutoff_frequency / samplingFrequency)
    gg0 = g / (1 + g)
    rr = (1 - g) / (1 + g)
    kk = 4 * (resonance ^ 1.5)
    gg4 = gg0 ^ 4

    b0 = gg4
    b1 = 4 * gg4
    b2 = 6 * gg4
    b3 = 4 * gg4
    b4 = gg4

    d0 = 1 + kk * gg4
    d1 = -4 * rr + 4 * kk * gg4
    d2 = 6 * rr^2 + 6 * kk * gg4
    d3 = -4 * rr^3 + 4 * kk * gg4
    d4 = rr^4 + kk * gg4

    appendInfoLine: "TPT: g=", fixed$(g, 6), "  G=", fixed$(gg0, 6), "  k=", fixed$(kk, 4)

    selectObject: resultID
    Formula: "(" + string$(b0) + "*object[" + soundId$ + ",row,col]"
        ... + " + (if col>1 then " + string$(b1) + "*object[" + soundId$ + ",row,col-1] else 0 fi)"
        ... + " + (if col>2 then " + string$(b2) + "*object[" + soundId$ + ",row,col-2] else 0 fi)"
        ... + " + (if col>3 then " + string$(b3) + "*object[" + soundId$ + ",row,col-3] else 0 fi)"
        ... + " + (if col>4 then " + string$(b4) + "*object[" + soundId$ + ",row,col-4] else 0 fi)"
        ... + " - (if col>1 then " + string$(d1) + "*self[col-1] else 0 fi)"
        ... + " - (if col>2 then " + string$(d2) + "*self[col-2] else 0 fi)"
        ... + " - (if col>3 then " + string$(d3) + "*self[col-3] else 0 fi)"
        ... + " - (if col>4 then " + string$(d4) + "*self[col-4] else 0 fi)) / " + string$(d0)

else
    appendInfoLine: "Building sample-continuous coefficient trajectories..."

    # Controls are indexed by sample number, so non-zero Sound start times
    # do not alter the automation trajectory or the result.
    cutoffId = Create Sound from formula: "moog_cutoff_control", 1, 0, numberOfSamples / samplingFrequency,
        ... samplingFrequency,
        ... string$(start_cutoff) + " * exp(ln(" + string$(end_cutoff / start_cutoff) + ") * x / " + string$(duration) + ")"
    resonanceId = Create Sound from formula: "moog_res_control", 1, 0, numberOfSamples / samplingFrequency,
        ... samplingFrequency,
        ... string$(start_resonance) + " + (" + string$(end_resonance - start_resonance) + ") * x / " + string$(duration)

    selectObject: cutoffId
    gg4Id = Copy: "moog_G4"
    Formula: "(tan(pi*self/" + string$(samplingFrequency) + ") / (1 + tan(pi*self/" + string$(samplingFrequency) + "))) ^ 4"
    selectObject: cutoffId
    rrId = Copy: "moog_R"
    Formula: "(1 - tan(pi*self/" + string$(samplingFrequency) + ")) / (1 + tan(pi*self/" + string$(samplingFrequency) + "))"
    selectObject: resonanceId
    kkId = Copy: "moog_k"
    Formula: "4 * self ^ 1.5"

    g4s$ = "object[" + string$(gg4Id) + ",1,col]"
    rrs$ = "object[" + string$(rrId) + ",1,col]"
    kks$ = "object[" + string$(kkId) + ",1,col]"

    xsum$ = "object[" + soundId$ + ",row,col]"
        ... + " + 4*(if col>1 then object[" + soundId$ + ",row,col-1] else 0 fi)"
        ... + " + 6*(if col>2 then object[" + soundId$ + ",row,col-2] else 0 fi)"
        ... + " + 4*(if col>3 then object[" + soundId$ + ",row,col-3] else 0 fi)"
        ... + " + (if col>4 then object[" + soundId$ + ",row,col-4] else 0 fi)"

    d1s$ = "(-4*" + rrs$ + " + 4*" + kks$ + "*" + g4s$ + ")"
    d2s$ = "(6*" + rrs$ + "^2 + 6*" + kks$ + "*" + g4s$ + ")"
    d3s$ = "(-4*" + rrs$ + "^3 + 4*" + kks$ + "*" + g4s$ + ")"
    d4s$ = "(" + rrs$ + "^4 + " + kks$ + "*" + g4s$ + ")"
    d0s$ = "(1 + " + kks$ + "*" + g4s$ + ")"

    selectObject: resultID
    Formula: "(" + g4s$ + "*(" + xsum$ + ")"
        ... + " - " + d1s$ + "*(if col>1 then self[col-1] else 0 fi)"
        ... + " - " + d2s$ + "*(if col>2 then self[col-2] else 0 fi)"
        ... + " - " + d3s$ + "*(if col>3 then self[col-3] else 0 fi)"
        ... + " - " + d4s$ + "*(if col>4 then self[col-4] else 0 fi)) / " + d0s$
endif

# ============================================================
# OUTPUT GAIN + OPTIONAL SATURATION
# ============================================================
selectObject: resultID
if trimGain <> 1
    Formula: "self * " + string$(trimGain)
endif

if limiter_type = 2
    Formula: "self / (1 + abs(self))"
elsif limiter_type = 3
    Formula: "tanh(self)"
endif

# DC blocker: y[n] = x[n] - x[n-1] + a*y[n-1]
if dC_blocker
    selectObject: resultID
    dcInput = Copy: "moog_dc_input"
    dcIn$ = string$(dcInput)
    alpha_dc = exp(-2 * pi * 20 / samplingFrequency)
    selectObject: resultID
    Formula: "object[" + dcIn$ + ",row,col]"
        ... + " - (if col>1 then object[" + dcIn$ + ",row,col-1] else 0 fi)"
        ... + " + " + string$(alpha_dc) + "*(if col>1 then self[col-1] else 0 fi)"
    removeObject: dcInput
endif

# Coefficient-object cleanup after processing.
if use_automation
    removeObject: cutoffId, resonanceId, gg4Id, rrId, kkId
endif

selectObject: soundID
peakIn = Get absolute extremum: 0, 0, "None"
selectObject: resultID
peakOut = Get absolute extremum: 0, 0, "None"
if limiter_type = 1 and peakOut > 1
    appendInfoLine: "Warning: output peak ", fixed$(peakOut, 4), " exceeds +/-1.0 (linear mode; no normalization)."
endif

# ============================================================
# VISUALIZATION - Praat AudioTools house style
# ============================================================
if draw_visualization
    appendInfoLine: "Creating AudioTools visualization..."
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    selectObject: soundID
    if numberOfChannels > 1
        vizIn = Convert to mono
    else
        vizIn = Copy: "moog_viz_in"
    endif
    selectObject: resultID
    if numberOfChannels > 1
        vizOut = Convert to mono
    else
        vizOut = Copy: "moog_viz_out"
    endif

    # Title
    suiteVizName$ = replace$(soundName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Moog-Style TPT Ladder Filter v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: vizIn
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: vizOut
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Paired spectra
    vizMaxHz = min(10000, nyquist)
    if vizMaxHz > 100
        Select outer viewport: 0, 4.1, 2.24, 3.64
        Select inner viewport: 0.55, 3.85, 2.34, 3.54
        selectObject: vizIn
        specIn = To Spectrum: "yes"
        Colour: "{0.55, 0.55, 0.55}"
        Draw: 0, vizMaxHz, 0, 80, "yes"
        removeObject: specIn
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "dB"
        Text bottom: "yes", "Hz"
        Text top: "no", "Input spectrum"

        Select outer viewport: 4.1, 8, 2.24, 3.64
        Select inner viewport: 4.40, 7.65, 2.34, 3.54
        selectObject: vizOut
        specOut = To Spectrum: "yes"
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, vizMaxHz, 0, 80, "yes"
        removeObject: specOut
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "dB"
        Text bottom: "yes", "Hz"
        Text top: "no", "Filtered spectrum"
    endif

    # Filter diagnostic panel
    Select outer viewport: 0, 8, 3.72, 5.05
    Select inner viewport: 0.60, 7.65, 3.82, 4.95
    if use_automation
        ymaxCut = max(start_cutoff, end_cutoff) * 1.12
        yminCut = min(start_cutoff, end_cutoff) * 0.75
        if yminCut < 0
            yminCut = 0
        endif
        Axes: 0, duration, yminCut, ymaxCut
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, yminCut, ymaxCut
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 2
        prevT = 0
        prevC = start_cutoff
        for q from 1 to 160
            tt = duration * q / 160
            cc = start_cutoff * exp(ln(end_cutoff / start_cutoff) * (tt / duration))
            Draw line: prevT, prevC, tt, cc
            prevT = tt
            prevC = cc
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Cutoff (Hz)"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Continuous cutoff automation (filter state is not reset)"
    else
        loResp = max(20, cutoff_frequency / 8)
        hiResp = min(nyquist * 0.95, cutoff_frequency * 16)
        if hiResp <= loResp * 1.2
            hiResp = min(nyquist * 0.95, loResp * 2)
        endif
        logLo = log10(loResp)
        logHi = log10(hiResp)
        Axes: logLo, logHi, -72, 30
        Paint rectangle: "{0.97, 0.97, 0.97}", logLo, logHi, -72, 30
        Colour: "{0.88, 0.88, 0.88}"
        dbLine = -60
        while dbLine <= 20
            Draw line: logLo, dbLine, logHi, dbLine
            dbLine = dbLine + 20
        endwhile

        # Evaluate the exact static transfer H(e^jw).
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 2
        prevX = undefined
        prevDb = undefined
        for q from 0 to 240
            lf = logLo + (logHi - logLo) * q / 240
            ff = 10 ^ lf
            ww = 2 * pi * ff / samplingFrequency
            # |B|^2 = G^8 * |1+e^-jw|^8 = G^8 * (2+2cos w)^4
            bmag2 = gg4^2 * (2 + 2*cos(ww))^4
            # D(q)=d0+d1 q+d2 q^2+d3 q^3+d4 q^4
            dre = d0 + d1*cos(ww) + d2*cos(2*ww) + d3*cos(3*ww) + d4*cos(4*ww)
            dim = -(d1*sin(ww) + d2*sin(2*ww) + d3*sin(3*ww) + d4*sin(4*ww))
            dmag2 = dre^2 + dim^2
            if bmag2 <= 0 or dmag2 <= 0
                respDb = -72
            else
                respDb = 10 * log10(bmag2 / dmag2)
                if respDb < -72
                    respDb = -72
                elsif respDb > 30
                    respDb = 30
                endif
            endif
            if q > 0
                Draw line: prevX, prevDb, lf, respDb
            endif
            prevX = lf
            prevDb = respDb
        endfor
        Line width: 1
        Colour: "{0.45, 0.45, 0.45}"
        Dotted line
        Draw line: log10(cutoff_frequency), -72, log10(cutoff_frequency), 30
        Solid line
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Gain (dB)"
        Text bottom: "yes", "Frequency (Hz, log)"
        Text top: "no", "Exact linear ladder response  |  asymptotic slope 24 dB/oct"
    endif

    # Summary
    Select outer viewport: 0, 8, 5.15, 5.90
    Select inner viewport: 0.55, 7.65, 5.22, 5.84
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.48, "half",
        ... "Preset: " + presetName$ + "  |  Channels: " + string$(numberOfChannels)
        ... + "  |  SR: " + fixed$(samplingFrequency, 0) + " Hz  |  Saturation: " + limiterName$
    Text: 0.02, "left", 0.18, "half",
        ... "Peak: " + fixed$(peakIn, 4) + " -> " + fixed$(peakOut, 4)
        ... + "  |  DC blocker: " + if dC_blocker then "on" else "off" fi
        ... + "  |  Trim: " + fixed$(output_trim_dB, 1) + " dB"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizIn, vizOut
    appendInfoLine: "Visualization complete."
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", soundName$, "_moog_", presetName$
appendInfoLine: "Peak: ", fixed$(peakIn, 4), " -> ", fixed$(peakOut, 4)
appendInfoLine: "Core: linearized TPT ladder; optional saturation is post-filter."

selectObject: resultID
if play_result
    Play
endif