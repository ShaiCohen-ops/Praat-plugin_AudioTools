# ============================================================
# Praat AudioTools - Pitch-Based_Spectral_Notch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.2 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Description:
#   Static pitch-based spectral notch filter.
#
#   1. Estimates the mean F0 over voiced frames.
#   2. Multiplies that mean F0 by Harmonic_number.
#   3. Builds one STATIC stop band whose total width is specified
#      in semitones around that centre frequency.
#   4. Applies Praat's Hann-smoothed spectral stop-band filter
#      identically to every input channel.
#
#   This is intentionally NOT a time-varying pitch tracker. For a
#   moving F0, the notch remains fixed at the mean-F0 target.
#
#   The filter is zero-phase frequency-domain filtering. Praat's
#   Hann smoothing defines the transition width between stop/pass.
#
#   Multichannel input is preserved. Dry/Wet=0 is an exact bypass.
#   Safety_peak only attenuates processed output above the ceiling;
#   it never boosts quieter material.
# ============================================================

form Pitch-Based Spectral Notch v1.2
    comment === PRESETS ===
    optionmenu Preset 1
        option Custom
        option Remove Fundamental
        option Remove Second Harmonic
        option Remove Upper Harmonics (4th)
        option Wide Notch
        option Narrow Notch
    comment === Pitch Analysis ===
    positive Min_pitch 75
    positive Max_pitch 600
    comment === Notch Parameters ===
    positive Harmonic_number 1
    positive Notch_width_semitones 6
    positive Smoothing_hz 50
    comment === Mix ===
    real Dry_wet_mix 1.0
    comment (1.0 = full wet, 0.0 = exact dry bypass)
    comment === Output ===
    real Safety_peak 0.99
    comment (0 disables; only attenuates, never boosts)
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset = 2
    harmonic_number = 1
    notch_width_semitones = 4
    smoothing_hz = 40
    presetName$ = "RemoveFundamental"
elsif preset = 3
    harmonic_number = 2
    notch_width_semitones = 4
    smoothing_hz = 40
    presetName$ = "RemoveSecond"
elsif preset = 4
    harmonic_number = 4
    notch_width_semitones = 18
    smoothing_hz = 100
    presetName$ = "RemoveUpper"
elsif preset = 5
    harmonic_number = 1
    notch_width_semitones = 12
    smoothing_hz = 80
    presetName$ = "WideNotch"
elsif preset = 6
    harmonic_number = 1
    notch_width_semitones = 2
    smoothing_hz = 20
    presetName$ = "NarrowNotch"
else
    presetName$ = "Custom"
endif

# ============================================================
# Validate input and parameters
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
sourceXmin = Get start time
nyquist = sampleRate / 2

if duration <= 0
    exitScript: "Sound has zero duration."
endif
if min_pitch >= max_pitch
    exitScript: "Min_pitch must be lower than Max_pitch."
endif
if harmonic_number <= 0
    exitScript: "Harmonic_number must be greater than zero."
endif

if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

if safety_peak < 0
    safety_peak = 0
elsif safety_peak > 1
    safety_peak = 1
endif

if smoothing_hz > nyquist / 2
    smoothing_hz = nyquist / 2
endif

# ============================================================
# Pitch analysis / notch geometry
# ============================================================
clearinfo
writeInfoLine: "=== Pitch-Based Spectral Notch v1.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$, "  (", numChannels, " ch, ",
    ... fixed$(sampleRate, 0), " Hz)"
appendInfoLine: "Duration: ", fixed$(duration, 3), " s   start ",
    ... fixed$(sourceXmin, 3), " s"
appendInfoLine: ""

meanPitch = undefined
notchCenter = undefined
notchLow = undefined
notchHigh = undefined
notchActive = 0
pitchObj = 0
soundMono = 0

if dry_wet_mix = 0
    appendInfoLine: "Dry/Wet = 0: exact bypass; pitch analysis skipped."
else
    appendInfoLine: "Step 1: Analyzing mean pitch..."

    analysisSource$ = "mono analysis"

    if numChannels > 1
        selectObject: sound
        soundMono = Convert to mono
    else
        selectObject: sound
        soundMono = Copy: "notch_pitch_analysis"
    endif

    selectObject: soundMono
    pitchObj = To Pitch: 0.01, min_pitch, max_pitch
    selectObject: pitchObj
    meanPitch = Get mean: 0, 0, "Hertz"

    # A normal mono sum is desirable for shared-content stereo, but it can
    # cancel completely for anti-phase channels. If that happens, fall back
    # to the individual channel with the most voiced Pitch frames.
    if meanPitch = undefined and numChannels > 1
        removeObject: pitchObj, soundMono
        pitchObj = 0
        soundMono = 0

        bestVoiced = -1
        bestChannel = 0
        meanPitch = undefined

        for ch from 1 to numChannels
            selectObject: sound
            chSound = Extract one channel: ch
            selectObject: chSound
            chPitch = To Pitch: 0.01, min_pitch, max_pitch
            selectObject: chPitch
            chVoiced = Count voiced frames
            chMean = Get mean: 0, 0, "Hertz"

            if chMean <> undefined and chVoiced > bestVoiced
                bestVoiced = chVoiced
                bestChannel = ch
                meanPitch = chMean
            endif

            removeObject: chPitch, chSound
        endfor

        if meanPitch <> undefined
            analysisSource$ = "channel " + string$(bestChannel) + " fallback"
        endif
    else
        removeObject: pitchObj, soundMono
        pitchObj = 0
        soundMono = 0
    endif

    if meanPitch = undefined
        exitScript: "No pitch detected. The static pitch-based notch needs voiced/pitched content." + newline$
            ... + "Try adjusting Min_pitch / Max_pitch."
    endif

    notchCenter = meanPitch * harmonic_number

    # notch_width_semitones is the TOTAL logarithmic width.
    halfWidthRatio = 2 ^ (notch_width_semitones / 24)
    notchLowRaw = notchCenter / halfWidthRatio
    notchHighRaw = notchCenter * halfWidthRatio

    if notchLowRaw < nyquist and notchHighRaw > 0
        notchLow = max(0.001, notchLowRaw)
        notchHigh = min(nyquist, notchHighRaw)
        if notchHigh > notchLow
            notchActive = 1
        endif
    endif

    appendInfoLine: "  Mean F0: ", fixed$(meanPitch, 2), " Hz"
    appendInfoLine: "  Target multiplier: ", fixed$(harmonic_number, 3),
        ... " x F0"
    appendInfoLine: "  Target centre: ", fixed$(notchCenter, 2), " Hz"
    appendInfoLine: "  Requested width: ", fixed$(notch_width_semitones, 2),
        ... " semitones total"
    if notchActive
        appendInfoLine: "  Applied stop band: ", fixed$(notchLow, 2),
            ... " - ", fixed$(notchHigh, 2), " Hz"
        if notchHighRaw > nyquist
            appendInfoLine: "  Note: upper edge clipped at Nyquist (",
                ... fixed$(nyquist, 1), " Hz)."
        endif
    else
        appendInfoLine: "  Target band lies outside the sampled spectrum; no notch applied."
    endif
    appendInfoLine: "  Hann transition width: ", fixed$(smoothing_hz, 1), " Hz"

    appendInfoLine: "  Pitch analysis source: ", analysisSource$
endif

# ============================================================
# Store original spectrum for visualization
# ============================================================
if draw_visualization
    selectObject: sound
    if numChannels > 1
        vizOrigMono = Convert to mono
    else
        vizOrigMono = Copy: "notch_viz_input"
    endif
    selectObject: vizOrigMono
    Shift times to: "start time", 0

    selectObject: vizOrigMono
    vizOrigSpectrum = To Spectrum: "yes"
    selectObject: vizOrigSpectrum
    To Matrix
    vizOrigMatrix = selected("Matrix")

    selectObject: vizOrigMatrix
    nFreqBins = Get number of columns

    nVizBins = 500
    viz_freq# = zero#(nVizBins)
    viz_mag_orig_lin# = zero#(nVizBins)

    for i from 1 to nVizBins
        freq = (i - 1) * nyquist / (nVizBins - 1)
        viz_freq#[i] = freq
        bin = 1 + round(freq * (nFreqBins - 1) / nyquist)
        if bin < 1
            bin = 1
        elsif bin > nFreqBins
            bin = nFreqBins
        endif
        re = Get value in cell: 1, bin
        im = Get value in cell: 2, bin
        viz_mag_orig_lin#[i] = sqrt(re^2 + im^2)
    endfor

    removeObject: vizOrigMatrix
endif

# ============================================================
# Apply one static multichannel filter
# ============================================================
appendInfoLine: ""
appendInfoLine: "Step 2: Applying static Hann stop band..."

processed = 0

if dry_wet_mix = 0 or notchActive = 0
    selectObject: sound
    finalOutput = Copy: "notch_output"
else
    selectObject: sound
    filtered = Filter (stop Hann band): notchLow, notchHigh, smoothing_hz
    processed = 1

    if dry_wet_mix < 1
        selectObject: filtered
        Formula: string$(dry_wet_mix) + " * self + "
            ... + string$(1 - dry_wet_mix) + " * object[" + string$(sound) + ", row, col]"
    endif

    finalOutput = filtered
endif

# ============================================================
# Safety attenuation (never normalization / never boost)
# ============================================================
selectObject: finalOutput
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
safetyApplied = 0

if processed and safety_peak > 0 and peakBeforeSafety > safety_peak
    safetyGain = safety_peak / peakBeforeSafety
    Formula: "self * " + string$(safetyGain)
    safetyApplied = 1
endif

selectObject: finalOutput
peakAfterSafety = Get absolute extremum: 0, 0, "None"
Rename: originalName$ + "_notched_" + presetName$

appendInfoLine: "  Filter path complete."
if safetyApplied
    appendInfoLine: "  Safety attenuation: peak ", fixed$(peakBeforeSafety, 4),
        ... " -> ", fixed$(peakAfterSafety, 4)
else
    appendInfoLine: "  Peak: ", fixed$(peakAfterSafety, 4),
        ... " (no normalization / no boost)"
endif

# ============================================================
# Store result spectrum for visualization
# ============================================================
if draw_visualization
    selectObject: finalOutput
    if numChannels > 1
        vizResultMono = Convert to mono
    else
        vizResultMono = Copy: "notch_viz_output"
    endif
    selectObject: vizResultMono
    Shift times to: "start time", 0

    selectObject: vizResultMono
    vizResultSpectrum = To Spectrum: "yes"
    selectObject: vizResultSpectrum
    To Matrix
    vizResultMatrix = selected("Matrix")

    viz_mag_result_lin# = zero#(nVizBins)
    selectObject: vizResultMatrix
    for i from 1 to nVizBins
        freq = viz_freq#[i]
        bin = 1 + round(freq * (nFreqBins - 1) / nyquist)
        if bin < 1
            bin = 1
        elsif bin > nFreqBins
            bin = nFreqBins
        endif
        re = Get value in cell: 1, bin
        im = Get value in cell: 2, bin
        viz_mag_result_lin#[i] = sqrt(re^2 + im^2)
    endfor

    removeObject: vizResultMatrix

    # Shared input-spectrum reference, so level changes remain visible.
    refMag = 0
    for i from 1 to nVizBins
        if viz_mag_orig_lin#[i] > refMag
            refMag = viz_mag_orig_lin#[i]
        endif
    endfor
    if refMag <= 0
        refMag = 1e-20
    endif

    viz_mag_orig# = zero#(nVizBins)
    viz_mag_result# = zero#(nVizBins)
    viz_delta# = zero#(nVizBins)

    for i from 1 to nVizBins
        viz_mag_orig#[i] = 20 * log10((viz_mag_orig_lin#[i] + 1e-20) / refMag)
        viz_mag_result#[i] = 20 * log10((viz_mag_result_lin#[i] + 1e-20) / refMag)

        if viz_mag_orig#[i] > -90
            viz_delta#[i] = viz_mag_result#[i] - viz_mag_orig#[i]
            if viz_delta#[i] < -70
                viz_delta#[i] = -70
            elsif viz_delta#[i] > 12
                viz_delta#[i] = 12
            endif
        else
            viz_delta#[i] = 0
        endif
    endfor
endif

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Step 3: Drawing visualization..."

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Helvetica
    Line width: 1

    colIn$ = "{0.55, 0.55, 0.55}"
    colOut$ = "{0.20, 0.40, 0.80}"
    colAcc$ = "{0.45, 0.35, 0.75}"
    colBg$ = "{0.97, 0.97, 0.97}"
    colGrid$ = "{0.87, 0.87, 0.87}"
    colText$ = "{0.35, 0.35, 0.45}"

    vizDuration = min(duration, 10)
    maxFreqDisplay = min(nyquist, 4000)
    if notchActive and notchHigh * 1.25 > maxFreqDisplay
        maxFreqDisplay = min(nyquist, notchHigh * 1.25)
    endif

    # --- Title ---------------------------------------------------------
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Pitch-Based Spectral Notch v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4, 0.55, 1.70
    Select inner viewport: 0.55, 3.80, 0.65, 1.62
    selectObject: vizOrigMono
    Colour: colIn$
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"

    Select outer viewport: 4, 8, 0.55, 1.70
    Select inner viewport: 4.25, 7.70, 0.65, 1.62
    selectObject: vizResultMono
    Colour: colOut$
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Text bottom: "yes", "Time (s)"

    # --- Spectrograms --------------------------------------------------
    Select outer viewport: 0, 4, 1.85, 3.70
    Select inner viewport: 0.55, 3.80, 1.95, 3.62
    selectObject: vizOrigMono
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specIn = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Axes: 0, vizDuration, 0, maxFreqDisplay
    if notchActive
        Colour: colAcc$
        Dotted line
        Draw line: 0, notchLow, vizDuration, notchLow
        Draw line: 0, notchCenter, vizDuration, notchCenter
        Draw line: 0, notchHigh, vizDuration, notchHigh
        Solid line
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input spectrogram"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    removeObject: specIn

    Select outer viewport: 4, 8, 1.85, 3.70
    Select inner viewport: 4.25, 7.70, 1.95, 3.62
    selectObject: vizResultMono
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Axes: 0, vizDuration, 0, maxFreqDisplay
    if notchActive
        Colour: colAcc$
        Dotted line
        Draw line: 0, notchLow, vizDuration, notchLow
        Draw line: 0, notchCenter, vizDuration, notchCenter
        Draw line: 0, notchHigh, vizDuration, notchHigh
        Solid line
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output spectrogram"
    Text bottom: "yes", "Time (s)"
    removeObject: specOut

    # --- Spectrum comparison ------------------------------------------
    maxFreqPlot = min(maxFreqDisplay, nyquist)
    Select outer viewport: 0, 8, 3.85, 5.35
    Select inner viewport: 0.65, 7.70, 3.95, 5.27
    Axes: 0, maxFreqPlot, -80, 5
    Paint rectangle: colBg$, 0, maxFreqPlot, -80, 5

    Colour: colGrid$
    db = -60
    while db <= 0
        Draw line: 0, db, maxFreqPlot, db
        db = db + 20
    endwhile

    Colour: colIn$
    Line width: 1.5
    for i from 1 to nVizBins - 1
        f1 = viz_freq#[i]
        f2 = viz_freq#[i + 1]
        if f2 <= maxFreqPlot
            y1 = max(-80, viz_mag_orig#[i])
            y2 = max(-80, viz_mag_orig#[i + 1])
            Draw line: f1, y1, f2, y2
        endif
    endfor

    Colour: colOut$
    Line width: 1.8
    for i from 1 to nVizBins - 1
        f1 = viz_freq#[i]
        f2 = viz_freq#[i + 1]
        if f2 <= maxFreqPlot
            y1 = max(-80, viz_mag_result#[i])
            y2 = max(-80, viz_mag_result#[i + 1])
            Draw line: f1, y1, f2, y2
        endif
    endfor
    Line width: 1

    if notchActive
        Colour: colAcc$
        Dotted line
        Draw line: notchCenter, -80, notchCenter, 5
        Solid line
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Spectrum comparison (shared input reference)"
    Text left: "yes", "Magnitude (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Font size: 6
    Colour: colIn$
    Text: maxFreqPlot * 0.02, "left", -5, "half", "input"
    Colour: colOut$
    Text: maxFreqPlot * 0.02, "left", -12, "half", "output"

    # --- Measured spectral change -------------------------------------
    Select outer viewport: 0, 8, 5.50, 6.65
    Select inner viewport: 0.65, 7.70, 5.60, 6.57
    Axes: 0, maxFreqPlot, -70, 12
    Paint rectangle: colBg$, 0, maxFreqPlot, -70, 12
    Colour: colGrid$
    Draw line: 0, 0, maxFreqPlot, 0
    Draw line: 0, -20, maxFreqPlot, -20
    Draw line: 0, -40, maxFreqPlot, -40
    Draw line: 0, -60, maxFreqPlot, -60

    Colour: colAcc$
    Line width: 1.8
    for i from 1 to nVizBins - 1
        f1 = viz_freq#[i]
        f2 = viz_freq#[i + 1]
        if f2 <= maxFreqPlot
            Draw line: f1, viz_delta#[i], f2, viz_delta#[i + 1]
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Measured output - input spectrum"
    Text left: "yes", "Change (dB)"
    Text bottom: "yes", "Frequency (Hz)"

    # --- Summary -------------------------------------------------------
    Select outer viewport: 0, 8, 6.80, 7.55
    Select inner viewport: 0.55, 7.70, 6.86, 7.49
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if notchActive
        Text: 0.02, "left", 0.72, "half",
            ... "##Notch##  centre " + fixed$(notchCenter, 1) + " Hz"
            ... + "  band " + fixed$(notchLow, 1) + "-" + fixed$(notchHigh, 1) + " Hz"
            ... + "  width " + fixed$(notch_width_semitones, 2) + " st"
            ... + "  transition " + fixed$(smoothing_hz, 1) + " Hz"
    else
        Text: 0.02, "left", 0.72, "half", "##Notch##  inactive / bypass"
    endif
    Text: 0.02, "left", 0.40, "half",
        ... "##Output##  " + string$(numChannels) + " ch"
        ... + "  wet " + fixed$(dry_wet_mix * 100, 0) + "%"
        ... + "  peak " + fixed$(peakBeforeSafety, 4) + " -> " + fixed$(peakAfterSafety, 4)
        ... + "  start " + fixed$(sourceXmin, 3) + " s"
    Text: 0.02, "left", 0.10, "half",
        ... "Static mean-F0 notch; identical spectral filter applied independently to every channel."
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"

    removeObject: vizOrigMono, vizOrigSpectrum, vizResultMono, vizResultSpectrum
    appendInfoLine: "  Visualization complete."
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# Final report
# ============================================================
selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", numChannels, " (preserved)"
appendInfoLine: "Start time: ", fixed$(sourceXmin, 3), " s"
if meanPitch <> undefined
    appendInfoLine: "Mean F0: ", fixed$(meanPitch, 2), " Hz"
    appendInfoLine: "Target: ", fixed$(harmonic_number, 3), " x F0 = ",
        ... fixed$(notchCenter, 2), " Hz"
endif
if notchActive
    appendInfoLine: "Applied band: ", fixed$(notchLow, 2), " - ",
        ... fixed$(notchHigh, 2), " Hz"
else
    appendInfoLine: "Applied band: none"
endif
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
appendInfoLine: "Peak: ", fixed$(peakAfterSafety, 4)
appendInfoLine: "Mode: static mean-pitch notch (not time-varying)"

if play_after_processing
    Play
endif