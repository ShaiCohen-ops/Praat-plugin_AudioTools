# ============================================================
# Praat AudioTools - Dynamic_Tremolo_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   A SPECTRAL tremolo / comb-colour effect. This is not conventional
#   time-domain tremolo: the gain is static in time and oscillates over
#   FREQUENCY below a cutoff. Above the cutoff a constant gain is used.
#
#       g(f) = g_min + depth * cos^2(pi*f / spacing)   , f < cutoff
#            = high_gain                              , f >= cutoff
#
#   spacing is the peak-to-peak spacing of the spectral gain comb in Hz.
#   The whole-file FFT implementation and its resulting colour/ringing are
#   deliberately retained as part of the instrument.
#
# Changelog v0.4 (2026):
#   - MUSICAL CLARITY: renamed the old Tremolo_rate control to Spectral
#     spacing (Hz). The old law cos(f/rate)^2 has period pi*rate, so presets
#     are converted exactly and the mono/full-quality spectral response is
#     unchanged for equivalent settings.
#   - FIX (stereo): Praat To Spectrum on a multichannel Sound averages the
#     channels. Stereo, especially anti-phase material, could therefore be
#     attenuated or cancelled before processing. Mono and stereo inputs are
#     now handled explicitly; L/R are processed independently with the same
#     gain law and recombined without changing their balance.
#   - QUALITY: Full Quality is now the default. The 22 kHz and 11 kHz speed
#     modes are explicitly labelled by their 11 kHz / 5.5 kHz bandwidth;
#     they are musical bandwidth reductions, not transparent speed switches.
#   - FIX: a requested cutoff above the working Nyquist now means "all of the
#     retained band is comb-shaped" instead of the old arbitrary 0.9*Nyquist
#     clamp that left the top 10% under high_gain.
#   - FIX: info reports requested vs effective cutoff after any resampling.
#   - FORM: zero minimum/depth/high gain are legal; output peak is bounded.
#   - VIZ: retained the existing story, but corrected the parts that could
#     mislead: representative stereo channel instead of L/R averaging,
#     adaptive frequency range, readable frequency marks, shared waveform
#     amplitude scale, and the exact spectral-spacing law.
#
# Changelog v0.3 (2026):
#   - FIX: preserve complex Spectrum rows with self*gain.
#   - FIX: cutoff/rate use frequency x in Hz, not FFT-bin col.
#   - FIX: trim FFT padding back to the working duration.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Dynamic Spectral Tremolo v0.4
    optionmenu Preset: 1
        option Custom
        option Classic Tremolo
        option Deep Tremolo
        option Subtle Shimmer
        option Fast Flutter
        option Slow Pulse
        option High Cut Tremolo
        option Bass Wobble
        option Spectral Sweep
    comment === Performance ===
    optionmenu Speed_mode: 1
        option Full Quality (original bandwidth)
        option Balanced (22 kHz render / 11 kHz bandwidth)
        option Fast (11 kHz render / 5.5 kHz bandwidth)
    comment === Spectral Tremolo ===
    positive Low_freq_cutoff_Hz 8000
    real Minimum_gain 0.3
    real Modulation_depth 0.7
    positive Spectral_spacing_Hz 1570.796327
    comment (spacing = peak-to-peak distance of the spectral comb)
    real High_freq_gain 0.8
    comment (constant gain above the cutoff)
    comment === Output ===
    real Output_peak 0.9
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS -- spacing = pi * the v0.3 "rate", preserving the response
# ============================================================

if preset = 2
    low_freq_cutoff_Hz = 8000
    minimum_gain = 0.3
    modulation_depth = 0.7
    spectral_spacing_Hz = pi * 500
    high_freq_gain = 0.8
    presetName$ = "ClassicTremolo"
elsif preset = 3
    low_freq_cutoff_Hz = 8000
    minimum_gain = 0.2
    modulation_depth = 0.9
    spectral_spacing_Hz = pi * 400
    high_freq_gain = 0.7
    presetName$ = "DeepTremolo"
elsif preset = 4
    low_freq_cutoff_Hz = 10000
    minimum_gain = 0.5
    modulation_depth = 0.3
    spectral_spacing_Hz = pi * 600
    high_freq_gain = 0.9
    presetName$ = "SubtleShimmer"
elsif preset = 5
    low_freq_cutoff_Hz = 6000
    minimum_gain = 0.3
    modulation_depth = 0.6
    spectral_spacing_Hz = pi * 150
    high_freq_gain = 0.8
    presetName$ = "FastFlutter"
elsif preset = 6
    low_freq_cutoff_Hz = 8000
    minimum_gain = 0.2
    modulation_depth = 0.8
    spectral_spacing_Hz = pi * 1000
    high_freq_gain = 0.85
    presetName$ = "SlowPulse"
elsif preset = 7
    low_freq_cutoff_Hz = 4000
    minimum_gain = 0.4
    modulation_depth = 0.5
    spectral_spacing_Hz = pi * 500
    high_freq_gain = 0.4
    presetName$ = "HighCutTremolo"
elsif preset = 8
    low_freq_cutoff_Hz = 2000
    minimum_gain = 0.2
    modulation_depth = 0.8
    spectral_spacing_Hz = pi * 300
    high_freq_gain = 1.0
    presetName$ = "BassWobble"
elsif preset = 9
    low_freq_cutoff_Hz = 12000
    minimum_gain = 0.1
    modulation_depth = 0.9
    spectral_spacing_Hz = pi * 800
    high_freq_gain = 0.6
    presetName$ = "SpectralSweep"
else
    presetName$ = "Custom"
endif

# Musically useful zero values are legal; negative gain controls are not.
if minimum_gain < 0
    exitScript: "Minimum gain must be >= 0."
endif
if modulation_depth < 0
    exitScript: "Modulation depth must be >= 0."
endif
if high_freq_gain < 0
    exitScript: "High-frequency gain must be >= 0."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be > 0 and <= 1."
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
nChannels = Get number of channels
if nChannels > 2
    exitScript: "Dynamic Spectral Tremolo currently supports mono or stereo Sound objects."
endif

if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced / 11 kHz bandwidth"
else
    targetSR = 11025
    speedStr$ = "Fast / 5.5 kHz bandwidth"
endif

# Prepare mono/stereo working channels explicitly. This avoids Praat's
# multichannel To Spectrum averaging and preserves stereo relationships.
if nChannels = 1
    selectObject: originalID
    workingL = Copy: "trem_work_M"
    workingR = 0
else
    selectObject: originalID
    workingL = Extract one channel: 1
    Rename: "trem_work_L"
    selectObject: originalID
    workingR = Extract one channel: 2
    Rename: "trem_work_R"
endif

# Optional bandwidth-reducing speed render.
didDownsample = 0
if targetSR > 0 and sampleRate > targetSR
    selectObject: workingL
    tmpL = Resample: targetSR, 50
    removeObject: workingL
    workingL = tmpL
    if nChannels = 2
        selectObject: workingR
        tmpR = Resample: targetSR, 50
        removeObject: workingR
        workingR = tmpR
    endif
    workingSR = targetSR
    didDownsample = 1
else
    workingSR = sampleRate
endif
workingNyquist = workingSR / 2
requestedCutoff = low_freq_cutoff_Hz
effectiveCutoff = min(requestedCutoff, workingNyquist)

# Formula constants used by the processing procedure.
cutoffStr$ = fixed$(effectiveCutoff, 9)
minStr$ = fixed$(minimum_gain, 9)
depthStr$ = fixed$(modulation_depth, 9)
spacingStr$ = fixed$(spectral_spacing_Hz, 9)
rateEquivalent = spectral_spacing_Hz / pi
rateEqStr$ = fixed$(rateEquivalent, 9)
highStr$ = fixed$(high_freq_gain, 9)

startTime = stopwatch
clearinfo
writeInfoLine: "=== DYNAMIC SPECTRAL TREMOLO v0.4 ==="
appendInfoLine: "Input: ", originalName$, "  |  channels: ", nChannels
appendInfoLine: "Duration: ", fixed$(duration, 3), " s  |  source SR: ", sampleRate, " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Render: ", speedStr$, "  |  working SR: ", workingSR, " Hz"
if effectiveCutoff < requestedCutoff
    appendInfoLine: "Cutoff: requested ", fixed$(requestedCutoff, 0), " Hz -> effective ", fixed$(effectiveCutoff, 1), " Hz (working Nyquist)"
else
    appendInfoLine: "Cutoff: ", fixed$(effectiveCutoff, 1), " Hz"
endif
appendInfoLine: "Gain range below cutoff: ", fixed$(minimum_gain, 3), " .. ", fixed$(minimum_gain + modulation_depth, 3)
appendInfoLine: "Spectral peak spacing: ", fixed$(spectral_spacing_Hz, 2), " Hz"
appendInfoLine: "High-band gain: ", fixed$(high_freq_gain, 3)
appendInfoLine: "Law: g(f)=g_min + depth*cos^2(pi*f/spacing); static in time"
appendInfoLine: ""
appendInfo: "Processing spectral tremolo..."

# ============================================================
# PROCESS
# ============================================================

@processChannel: workingL, "L"
processedL = processChannel.outID
if nChannels = 2
    @processChannel: workingR, "R"
    processedR = processChannel.outID
    selectObject: processedL
    plusObject: processedR
    resultID = Combine to stereo
    removeObject: processedL, processedR
else
    resultID = processedL
endif

# Working source copies are no longer needed.
if nChannels = 2
    removeObject: workingL, workingR
else
    removeObject: workingL
endif

# Return to the original sample rate if a speed render was used.
if didDownsample
    selectObject: resultID
    tmpOut = Resample: sampleRate, 50
    removeObject: resultID
    resultID = tmpOut
endif

# Joint peak scaling preserves stereo balance. Silence remains silence.
selectObject: resultID
resultPeakRaw = Get absolute extremum: 0, 0, "None"
if resultPeakRaw > 1e-12
    Scale peak: output_peak
endif
Rename: originalName$ + "_spectralTremolo_" + presetName$

appendInfoLine: " done"
processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION -- existing story retained, corrected where misleading
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Representative measured channel. For stereo, use the stronger source
    # channel rather than averaging L/R, which can cancel anti-phase material.
    if nChannels = 2
        selectObject: originalID
        vizOrigL = Extract one channel: 1
        selectObject: vizOrigL
        rmsVizL = Get root-mean-square: 0, 0
        selectObject: originalID
        vizOrigR = Extract one channel: 2
        selectObject: vizOrigR
        rmsVizR = Get root-mean-square: 0, 0
        if rmsVizR > rmsVizL
            vizChannel = 2
            vizOrig = vizOrigR
            removeObject: vizOrigL
            vizChan$ = "R"
        else
            vizChannel = 1
            vizOrig = vizOrigL
            removeObject: vizOrigR
            vizChan$ = "L"
        endif
        selectObject: resultID
        vizResult = Extract one channel: vizChannel
    else
        vizOrig = originalID
        vizResult = resultID
        vizChan$ = "mono"
    endif

    selectObject: vizOrig
    origSpecID = To Spectrum: "yes"
    selectObject: vizResult
    resSpecID = To Spectrum: "yes"

    selectObject: vizOrig
    peakOrigViz = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    peakResViz = Get absolute extremum: 0, 0, "None"
    wavePeak = 1.05 * max(peakOrigViz, peakResViz)
    if wavePeak < 1e-9
        wavePeak = 1
    endif

    # The spectrum panel must include the effective cutoff when possible.
    vizFreqMax = max(10000, effectiveCutoff * 1.20)
    vizFreqMax = min(sampleRate / 2, vizFreqMax)
    if vizFreqMax <= 5000
        freqTick = 1000
    elsif vizFreqMax <= 12000
        freqTick = 2000
    else
        freqTick = 4000
    endif

    Erase all

    # Title
    Select outer viewport: 0, 8, 0, 0.48
    Select inner viewport: 0, 8, 0, 0.48
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "Dynamic Spectral Tremolo: " + originalName$ + " [" + presetName$ + "]"
    Font size: 6
    Colour: "{0.35,0.35,0.42}"
    Text: 0.5, "centre", 0.12, "half", "static spectral comb gain; representative measured channel: " + vizChan$

    # Original waveform -- same scale as processed
    Select outer viewport: 0, 4, 0.58, 2.00
    Select inner viewport: 0.55, 3.72, 0.74, 1.82
    selectObject: vizOrig
    Colour: "{0.68,0.68,0.70}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Select inner viewport: 0.55, 3.72, 0.74, 1.82
    Axes: 0, duration, -wavePeak, wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Source"
    Text left: "yes", "Amp"

    # Processed waveform -- shared scale
    Select outer viewport: 4, 8, 0.58, 2.00
    Select inner viewport: 4.55, 7.72, 0.74, 1.82
    selectObject: vizResult
    Colour: "{0.24,0.50,0.80}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Select inner viewport: 4.55, 7.72, 0.74, 1.82
    Axes: 0, duration, -wavePeak, wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Spectral tremolo output"
    Text left: "yes", "Amp"

    # Spectrum comparison
    Select outer viewport: 0, 8, 2.12, 3.96
    Select inner viewport: 0.68, 7.70, 2.30, 3.68
    selectObject: origSpecID
    Colour: "{0.68,0.68,0.70}"
    Line width: 1
    Draw: 0, vizFreqMax, 0, 80, "no"
    selectObject: resSpecID
    Colour: "{0.24,0.50,0.80}"
    Line width: 1.5
    Draw: 0, vizFreqMax, 0, 80, "no"
    Select inner viewport: 0.68, 7.70, 2.30, 3.68
    Axes: 0, vizFreqMax, 0, 80
    Colour: "{0.86,0.28,0.25}"
    Dotted line
    if effectiveCutoff <= vizFreqMax
        Draw line: effectiveCutoff, 0, effectiveCutoff, 80
    endif
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, 20, "yes", "yes", "no"
    nTicks = floor(vizFreqMax / freqTick)
    for q from 0 to nTicks
        fMark = q * freqTick
        if fMark >= 1000
            fLab$ = fixed$(fMark/1000,1) + "k"
        else
            fLab$ = fixed$(fMark,0)
        endif
        One mark bottom: fMark, "no", "yes", "no", fLab$
    endfor
    Font size: 7
    Text top: "no", "Measured spectrum: gray source, blue output"
    Text left: "yes", "dB"

    Select outer viewport: 0, 8, 3.96, 4.14
    Select inner viewport: 0, 8, 3.96, 4.14
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.42}"
    if effectiveCutoff < requestedCutoff
        Text: 0.5, "centre", 0.5, "half", "frequency in Hz | effective cutoff " + fixed$(effectiveCutoff,0) + " Hz (requested " + fixed$(requestedCutoff,0) + ") | speed mode bandwidth-limited"
    else
        Text: 0.5, "centre", 0.5, "half", "frequency in Hz | cutoff " + fixed$(effectiveCutoff,0) + " Hz | same measured channel before/after"
    endif

    # Exact gain law -- this is the core mechanism panel.
    Select outer viewport: 0, 8, 4.22, 5.82
    Select inner viewport: 0.68, 7.70, 4.40, 5.52
    gainPlotMaxF = min(workingNyquist, max(effectiveCutoff * 1.20, min(10000, workingNyquist)))
    if gainPlotMaxF <= 0
        gainPlotMaxF = workingNyquist
    endif
    gainTop = 1.10 * max(high_freq_gain, minimum_gain + modulation_depth)
    if gainTop < 1
        gainTop = 1
    endif
    Axes: 0, gainPlotMaxF, 0, gainTop
    Colour: "{0.96,0.96,0.97}"
    Paint rectangle: "{0.96,0.96,0.97}", 0, gainPlotMaxF, 0, gainTop
    Colour: "{0.90,0.48,0.20}"
    Line width: 2
    numPoints = 300
    for i from 0 to numPoints - 1
        f1 = gainPlotMaxF * i / numPoints
        f2 = gainPlotMaxF * (i + 1) / numPoints
        if f1 < effectiveCutoff
            gain1 = minimum_gain + modulation_depth * cos(pi*f1/spectral_spacing_Hz)^2
        else
            gain1 = high_freq_gain
        endif
        if f2 < effectiveCutoff
            gain2 = minimum_gain + modulation_depth * cos(pi*f2/spectral_spacing_Hz)^2
        else
            gain2 = high_freq_gain
        endif
        Draw line: f1, gain1, f2, gain2
    endfor
    Line width: 1
    Dotted line
    Colour: "{0.86,0.28,0.25}"
    if effectiveCutoff <= gainPlotMaxF
        Draw line: effectiveCutoff, 0, effectiveCutoff, gainTop
    endif
    Solid line
    Select inner viewport: 0.68, 7.70, 4.40, 5.52
    Axes: 0, gainPlotMaxF, 0, gainTop
    Colour: "Black"
    Draw inner box
    Font size: 5
    if gainPlotMaxF <= 5000
        gainTick = 1000
    elsif gainPlotMaxF <= 12000
        gainTick = 2000
    else
        gainTick = 4000
    endif
    nGTicks = floor(gainPlotMaxF/gainTick)
    for q from 0 to nGTicks
        fMark = q*gainTick
        if fMark >= 1000
            fLab$ = fixed$(fMark/1000,1) + "k"
        else
            fLab$ = fixed$(fMark,0)
        endif
        One mark bottom: fMark, "no", "yes", "no", fLab$
    endfor
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Font size: 7
    Text top: "no", "Frequency-dependent gain law"
    Text left: "yes", "Gain"

    Select outer viewport: 0, 8, 5.82, 6.06
    Select inner viewport: 0, 8, 5.82, 6.06
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.42}"
    Text: 0.5, "centre", 0.5, "half", "g(f)=g_min + depth*cos^2(pi*f/spacing) below cutoff | spacing=" + fixed$(spectral_spacing_Hz,1) + " Hz | above cutoff gain=" + fixed$(high_freq_gain,2)

    # Compact QC strip
    Select outer viewport: 0, 8, 6.14, 6.72
    Select inner viewport: 0.18, 7.82, 6.18, 6.68
    Axes: 0, 3, 0, 1
    Colour: "{0.96,0.96,0.97}"
    Paint rectangle: "{0.96,0.96,0.97}", 0, 3, 0, 1
    Colour: "{0.82,0.82,0.84}"
    Draw line: 1,0,1,1
    Draw line: 2,0,2,1
    Colour: "Black"
    Draw rectangle: 0,3,0,1
    Font size: 6
    Text: 0.05,"left",0.5,"half","gain " + fixed$(minimum_gain,2) + ".." + fixed$(minimum_gain+modulation_depth,2) + " | cutoff " + fixed$(effectiveCutoff,0) + " Hz"
    Text: 1.05,"left",0.5,"half","spacing " + fixed$(spectral_spacing_Hz,1) + " Hz | " + speedStr$
    selectObject: resultID
    finalPeak = Get absolute extremum: 0,0,"None"
    finalRms = Get root-mean-square: 0,0
    Text: 2.05,"left",0.5,"half","peak " + fixed$(finalPeak,3) + " | RMS " + fixed$(finalRms,3) + " | " + fixed$(processingTime,2) + " s"

    removeObject: origSpecID, resSpecID
    if nChannels = 2
        removeObject: vizOrig, vizResult
    endif
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: resultID
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    Play
endif
selectObject: resultID

# ============================================================
# PROCEDURES
# ============================================================

procedure processChannel: .soundID, .label$
    selectObject: .soundID
    .dur = Get total duration
    To Spectrum: "yes"
    .spec = selected("Spectrum")
    selectObject: .spec
    Formula: "if x < " + cutoffStr$ + " then self * (" + minStr$ + " + " + depthStr$ + " * cos(x/" + rateEqStr$ + ")^2) else self * " + highStr$ + " fi"
    To Sound
    .padded = selected("Sound")
    selectObject: .padded
    Extract part: 0, .dur, "rectangular", 1, "no"
    .outID = selected("Sound")
    Rename: "trem_proc_" + .label$
    removeObject: .padded, .spec
endproc
