# ============================================================
# Praat AudioTools - Adaptive_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-varying spectral filter with a swept cutoff. Supports
#   lowpass, highpass, and bandpass modes with optional Gaussian
#   emphasis. FFT weighted-overlap-add processing.
#
#   Naming note: this is a DETERMINISTIC time-varying filter. It is
#   not an adaptive filter in the signal-processing sense - there is
#   no reference signal, no error, no LMS/RLS coefficient update.
#   Nothing here responds to the content of the input.
#
# Features:
#   - Filter types: Lowpass, Highpass, Bandpass
#   - Sweep curves: linear Hz, quadratic ease-in, log-frequency
#     with ease-out, cosine S-curve, true log-frequency
#   - Gaussian emphasis with adjustable width
#   - Mono and stereo
#   - Window-size modes for the time/frequency resolution tradeoff
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.1:
#   - Weighted overlap-add with padding. v1.0 used
#     nSegs = floor((duration - window) / hop) + 1, so any tail past
#     the last whole window was never written and stayed silent: up to
#     40 ms in Draft, and a 1.013 s file in Standard lost its final
#     13 ms outright. It also applied a Hanning window to every frame
#     without dividing by the accumulated window weight, so the file
#     faded in and out over half a window at each end. The signal is
#     now padded by one window on both sides, the window weights are
#     accumulated in their own buffer, and the sum is divided out.
#   - Non-zero xmin handled. v1.0 read only the duration and then
#     extracted from time 0, so a Sound living in [5, 6] was asked for
#     [0, 0.04]. The work copy is shifted to 0 and the result is
#     shifted back to the source's own start time.
#   - Integer sample indices. "Get sample number from time" returns a
#     REAL (882.5 is normal), and an index inside object[...] is
#     rounded, so frames could land one sample off - and differently
#     for the first frame, which was forced to 1. Offsets are computed
#     with round() now, and the end index that v1.0 computed but never
#     used actually bounds the write.
#   - The sweep reaches its stated endpoints. v1.0 took tNorm from the
#     window CENTRE, so the first frame started at tNorm = 0.02 and the
#     last ended at 0.98 in a 1 s file - and at 0.2 / 0.8 in a 100 ms
#     file - while the plot and the report both claimed the full range.
#     With padding, the first frame over the signal maps to exactly 0
#     and the last to exactly 1.
#   - Opening/Closing Highpass were backwards: raising a highpass
#     cutoff NARROWS the passband. The frequencies are swapped so the
#     names are true.
#   - Telephone Effect was not a bandpass. 800 Hz centre with 2600 Hz
#     width gives bpLow = -500 Hz, so the lower transition never
#     applied and the result passed from DC to 2100 Hz - a lowpass.
#     It is now 1850 Hz centre, 3100 Hz width, i.e. 300-3400 Hz.
#   - Bandpass edges clamped. bpLow and bpHigh themselves were never
#     clamped (only lowBound/highBound were), and the transition
#     formula divided by the unclamped smoothing width, so a clamped
#     edge did not reach 1 at the passband. Both edges are clamped and
#     each transition uses its own actual width.
#   - Resonance is described as what it is: the height of a Gaussian
#     emphasis, not a filter Q and not a pole. In lowpass and highpass
#     it multiplied a response that is 0.5 AT the cutoff, so
#     Resonance 0.8 gave 0.9 there - below the passband, not a peak.
#     Resonance_mode adds a "true peak at cutoff" option; the default
#     keeps v1.0's behaviour, and the gain at cutoff is now reported.
#   - Sweep curves renamed. "Exponential" was tNorm^2, a quadratic
#     ease-in; "Logarithmic" was log-frequency interpolation driven by
#     a sqrt ease-out. Both keep their behaviour under accurate names,
#     and a true log-frequency sweep is added as a fifth option.
#   - Quality modes renamed Smooth / Balanced / Responsive: a shorter
#     window tracks time better and resolves frequency worse, so
#     "High" was not a higher quality. A warning fires when the window
#     is too short for the frequencies being swept.
#   - Output level is a choice, default a ceiling that only attenuates.
#     v1.0 always ran Scale peak, so a heavily filtered result was
#     pushed back to 0.99 and the filter's own attenuation vanished.
#   - Sounds with more than 2 channels say so instead of silently
#     dropping channels 3 and up.
#   - The plot draws the bounds actually used, per frame, including
#     clamping and the transition bands.
#
# Changelog v1.2 (second static review; the v1.1 WOLA core passed):
#   - "True peak at cutoff" is now actually a peak at the cutoff. v1.1
#     used H0(f) + (0.5 + R) * G(f), which lands on the right VALUE at
#     the cutoff but leaves the slope there equal to H0'(cutoff), so the
#     maximum slid into the passband: cutoff 200 Hz with R = 0.8 peaked
#     at 1.957 near 180.3 Hz instead of 1.800 at 200 Hz. The response is
#     now H0(f) + ((1 + R) - H0(f)) * G(f); at the cutoff G = 1 so the
#     value is exactly 1 + R, and G'= 0 there cancels the H0 terms in
#     the derivative, so the maximum sits on the cutoff.
#   - The base response at the cutoff is computed, not assumed to be
#     0.5. It is 0.5 only when neither transition bound was clamped;
#     at cutoff 30 Hz with smoothing 50 Hz the low bound clamps to 0 and
#     the true value is about 0.691. v1.1 hard-coded 0.5 in both the
#     resonance formula and the reported gain, so both were wrong
#     wherever an edge clamped. The report now gives the range across
#     the sweep.
#   - Every channel is filtered and kept. v1.1 warned that channels 3
#     and up would be dropped, then dropped them: any non-mono input
#     went through a hard-coded two-channel branch. Channels are now
#     processed in a loop and written back row by row, which takes any
#     channel count.
#   - Resonant Sweep and Acid Bass select Resonance_mode 2, since their
#     names promise a peak that mode 1 does not produce.
#   - Start and end frequencies are clamped to [20 Hz, Nyquist - 100]
#     BEFORE freqRange, logStart and the report are derived from them.
#     v1.1 clamped only inside the frame loop, so a 5 Hz start was
#     reported as 5 Hz, seeded ln(5), and silently ran at 20 Hz.
#   - The frequency-resolution warning is computed after the window is
#     shortened for short files, and from the lowest filter EDGE in the
#     sweep rather than the centre frequency.
#   - Negative Resonance exits with a message instead of being silently
#     treated as no resonance by every "resonance <= 0" test.
#   - The plotted cutoff line covers every frame whose window overlaps
#     the file, so it no longer stops short of the shading when the
#     length is not a multiple of the hop.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Adaptive Filter v1.2
    optionmenu Preset: 1
        option Custom
        option Rising Lowpass (dark to bright)
        option Falling Lowpass (bright to dark)
        option Opening Highpass
        option Closing Highpass
        option Bandpass Sweep Up
        option Bandpass Sweep Down
        option Resonant Sweep
        option Acid Bass
        option Underwater
        option Telephone Effect
        option S-Curve Sweep
    comment === Filter Type ===
    optionmenu Filter_type: 1
        option Lowpass
        option Highpass
        option Bandpass
    comment === Frequency Sweep ===
    positive Start_frequency_(Hz) 200
    positive End_frequency_(Hz) 4000
    optionmenu Sweep_curve: 1
        option Linear Hz
        option Quadratic ease-in (linear Hz)
        option Log-frequency with ease-out
        option Cosine S-curve (linear Hz)
        option Log-frequency (constant octaves/s)
    comment === Bandpass Width ===
    positive Bandwidth_(Hz) 500
    comment === Gaussian Emphasis (not a filter Q) ===
    real Resonance 0.0
    positive Resonance_bandwidth_(Hz) 100
    optionmenu Resonance_mode: 1
        option Multiplied into the response (v1.0)
        option True peak at cutoff
    comment === Window ===
    optionmenu Quality_mode: 2
        option Smooth (80 ms window, best frequency resolution)
        option Balanced (40 ms window)
        option Responsive (20 ms window, best time resolution)
    comment === Output ===
    optionmenu Output_level_mode: 2
        option None (leave level as filtered)
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Rising Lowpass
    filter_type = 1
    start_frequency = 200
    end_frequency = 8000
    sweep_curve = 2
    resonance = 0.2
    resonance_bandwidth = 120
    preset$ = "Rising Lowpass"
elsif preset = 3
    # Falling Lowpass
    filter_type = 1
    start_frequency = 8000
    end_frequency = 300
    sweep_curve = 3
    resonance = 0.2
    resonance_bandwidth = 120
    preset$ = "Falling Lowpass"
elsif preset = 4
    # Opening Highpass: the passband OPENS as the highpass cutoff falls.
    # v1.0 had 200 -> 2000, which narrows the passband, i.e. closes it.
    filter_type = 2
    start_frequency = 3000
    end_frequency = 100
    sweep_curve = 1
    resonance = 0.3
    resonance_bandwidth = 100
    preset$ = "Opening Highpass"
elsif preset = 5
    # Closing Highpass: the passband CLOSES as the cutoff rises.
    filter_type = 2
    start_frequency = 200
    end_frequency = 2000
    sweep_curve = 1
    resonance = 0.3
    resonance_bandwidth = 100
    preset$ = "Closing Highpass"
elsif preset = 6
    # Bandpass Sweep Up
    filter_type = 3
    start_frequency = 300
    end_frequency = 3000
    bandwidth = 400
    sweep_curve = 1
    resonance = 0.0
    preset$ = "Bandpass Sweep Up"
elsif preset = 7
    # Bandpass Sweep Down
    filter_type = 3
    start_frequency = 4000
    end_frequency = 400
    bandwidth = 500
    sweep_curve = 1
    resonance = 0.0
    preset$ = "Bandpass Sweep Down"
elsif preset = 8
    # Resonant Sweep
    filter_type = 1
    start_frequency = 200
    end_frequency = 4000
    sweep_curve = 1
    resonance = 0.8
    resonance_bandwidth = 60
    # The name promises a peak, so it selects the mode that makes one.
    # Under the v1.0 multiplied mode this gave 0.9 at the cutoff, i.e.
    # a dip below the passband.
    resonance_mode = 2
    preset$ = "Resonant Sweep"
elsif preset = 9
    # Acid Bass
    filter_type = 1
    start_frequency = 150
    end_frequency = 3000
    sweep_curve = 2
    resonance = 1.2
    resonance_bandwidth = 40
    resonance_mode = 2
    preset$ = "Acid Bass"
elsif preset = 10
    # Underwater
    filter_type = 1
    start_frequency = 800
    end_frequency = 300
    sweep_curve = 4
    resonance = 0.3
    resonance_bandwidth = 150
    preset$ = "Underwater"
elsif preset = 11
    # Telephone Effect: 300-3400 Hz, the actual telephone band.
    # v1.0 used centre 800 / width 2600, giving bpLow = -500 Hz, so the
    # lower edge never engaged and the result was a lowpass to 2100 Hz.
    filter_type = 3
    start_frequency = 1850
    end_frequency = 1850
    bandwidth = 3100
    sweep_curve = 1
    resonance = 0.0
    preset$ = "Telephone"
elsif preset = 12
    # S-Curve Sweep
    filter_type = 1
    start_frequency = 200
    end_frequency = 6000
    sweep_curve = 4
    resonance = 0.4
    resonance_bandwidth = 80
    preset$ = "S-Curve Sweep"
else
    preset$ = "Custom"
endif

# Get filter type name
if filter_type = 1
    filterType$ = "Lowpass"
elsif filter_type = 2
    filterType$ = "Highpass"
else
    filterType$ = "Bandpass"
endif

# Get sweep curve name
if sweep_curve = 1
    curve$ = "Linear Hz"
elsif sweep_curve = 2
    curve$ = "Quadratic ease-in"
elsif sweep_curve = 3
    curve$ = "Log-freq + ease-out"
elsif sweep_curve = 4
    curve$ = "Cosine S-curve"
else
    curve$ = "Log-frequency"
endif

# Window size. A shorter window tracks time better and resolves
# frequency worse: this is a tradeoff, not a quality ranking, which is
# why these are no longer called Draft / Standard / High.
if quality_mode = 1
    window_size_s = 0.08
    quality$ = "Smooth"
elsif quality_mode = 2
    window_size_s = 0.04
    quality$ = "Balanced"
else
    window_size_s = 0.02
    quality$ = "Responsive"
endif

# ============================================================
# SETUP
# ============================================================
clearinfo
writeInfoLine: "=== Adaptive Filter v1.2 ==="
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Filter: ", filterType$, " | Curve: ", curve$, " | Window: ", quality$

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
srcStart = Get start time
nyquist = sampleRate / 2

if duration < 0.05
    exitScript: "Sound too short (minimum 0.05 seconds)."
endif

# Negative emphasis was accepted by the form and then silently treated
# as "no emphasis" by every "resonance <= 0" test, so it neither
# attenuated nor notched. Say so rather than ignoring it.
if resonance < 0
    exitScript: "Resonance must be 0 or greater (got " + fixed$(resonance, 2) +
    ... "). It is the height of a Gaussian boost; there is no attenuation or notch " +
    ... "behaviour defined for negative values."
endif

# --- Frequency clamping, BEFORE anything derived from it ---
# v1.1 clamped only inside the per-frame loop (max(20, ...)), so a
# 5 Hz start was reported as 5 Hz, fed logStart with ln(5), and then
# silently ran at 20 Hz for the opening stretch of the sweep.
minAllowedFreq = 20
maxAllowedFreq = nyquist - 100
if maxAllowedFreq <= minAllowedFreq
    exitScript: "Sampling rate " + fixed$(sampleRate, 0) + " Hz is too low for this filter."
endif

reqStart = start_frequency
reqEnd = end_frequency
start_frequency = min(max(start_frequency, minAllowedFreq), maxAllowedFreq)
end_frequency = min(max(end_frequency, minAllowedFreq), maxAllowedFreq)

if start_frequency <> reqStart
    appendInfoLine: "  Start frequency clamped: ", round(reqStart), " -> ",
    ... round(start_frequency), " Hz"
endif
if end_frequency <> reqEnd
    appendInfoLine: "  End frequency clamped: ", round(reqEnd), " -> ",
    ... round(end_frequency), " Hz"
endif

appendInfoLine: "Sweep: ", round(start_frequency), " -> ", round(end_frequency), " Hz"

if numChannels > 2
    appendInfoLine: "  ", numChannels, " channels: each is filtered separately and all are kept."
endif

# Pre-calculate sweep parameters from the CLAMPED frequencies
freqRange = end_frequency - start_frequency
logStart = ln(max(start_frequency, 1))
logEnd = ln(max(end_frequency, 1))
logRange = logEnd - logStart

# ============================================================
# FRAME PLAN
# ============================================================
# One window of zero padding on each side. That is what lets the first
# frame covering real signal map to sweep position 0 and the last to 1,
# and what lets the window weights sum to a usable value right to the
# first and last sample instead of fading in over half a window.

overlap = 0.5

# The effective window is settled here, before anything reports on it.
# v1.1 issued the frequency-resolution warning from the requested
# window, then shortened it for short files, so a 50 ms file in Smooth
# was judged as if it used an 80 ms window.
if window_size_s > duration
    windowRequested_s = window_size_s
    window_size_s = duration
    appendInfoLine: "  Window shortened to the file length: ",
    ... fixed$(windowRequested_s * 1000, 0), " -> ", fixed$(window_size_s * 1000, 0), " ms"
endif
hopDur = window_size_s * overlap

padDur = window_size_s
coreEnd = padDur + duration
nSegs = ceiling(coreEnd / hopDur) + 1
lastFrameEnd = (nSegs - 1) * hopDur + window_size_s
padTailDur = max(lastFrameEnd - coreEnd, padDur)

appendInfoLine: "Frames: ", nSegs, " (", fixed$(window_size_s * 1000, 0), " ms window, ",
... fixed$(hopDur * 1000, 0), " ms hop, ", fixed$(padDur * 1000, 0), " ms pad each side)"

# --- Per-frame filter parameters, computed once ---
# Channel-independent, so every channel reuses them, and the plot draws
# exactly the bounds the audio was filtered with.
lowestEdge = nyquist
gainCutMin = 1e9
gainCutMax = -1e9

for k from 1 to nSegs
    segStart = (k - 1) * hopDur
    segMid = segStart + window_size_s / 2
    # Position along the SOURCE, with the padding removed. Frames that
    # sit entirely in the head pad clamp to 0, frames past the tail
    # clamp to 1, so the sweep genuinely spans start to end.
    coreMid = segMid - padDur
    tNorm = coreMid / duration
    tNorm = min(max(tNorm, 0), 1)

    if sweep_curve = 1
        sweepPos = tNorm
    elsif sweep_curve = 2
        sweepPos = tNorm * tNorm
    elsif sweep_curve = 3
        sweepPos = sqrt(tNorm)
    elsif sweep_curve = 4
        sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
    else
        sweepPos = tNorm
    endif

    if (sweep_curve = 3 or sweep_curve = 5) and logRange <> 0
        cutoff = exp(logStart + sweepPos * logRange)
    else
        cutoff = start_frequency + sweepPos * freqRange
    endif

    cutoff = max(minAllowedFreq, min(maxAllowedFreq, cutoff))
    smoothing = max(50, cutoff * 0.15)

    fCut[k] = cutoff
    fSmooth[k] = smoothing

    if filter_type = 3
        # Clamp the passband edges themselves, not only the transition
        # bounds. v1.0 clamped lowBound/highBound but left bpLow
        # negative, so the lower transition branch never fired and the
        # "bandpass" passed everything down to DC.
        bpLowK = max(0, cutoff - bandwidth / 2)
        bpHighK = min(nyquist, cutoff + bandwidth / 2)
        if bpHighK <= bpLowK
            bpHighK = min(nyquist, bpLowK + 1)
        endif
        fBpLow[k] = bpLowK
        fBpHigh[k] = bpHighK
        fLow[k] = max(0, bpLowK - smoothing)
        fHigh[k] = min(nyquist, bpHighK + smoothing)
        # Each transition gets its OWN width, so a clamped edge still
        # reaches 1 at the passband instead of stopping short.
        fLoWidth[k] = bpLowK - fLow[k]
        fHiWidth[k] = fHigh[k] - bpHighK
        # Inside a bandpass the centre frequency sits in the flat part
        fH0Cut[k] = 1
        if bpLowK < lowestEdge
            lowestEdge = bpLowK
        endif
    else
        fLow[k] = max(0, cutoff - smoothing)
        fHigh[k] = min(nyquist, cutoff + smoothing)
        if fHigh[k] <= fLow[k]
            fHigh[k] = fLow[k] + 1
        endif
        # The base response AT the cutoff. It is 0.5 only when neither
        # bound was clamped; with cutoff = 30 Hz and smoothing = 50 Hz
        # the low bound clamps to 0 and the true value is about 0.69.
        # v1.1 assumed 0.5 in both the report and the "true peak"
        # formula, so both were wrong wherever an edge was clamped.
        phaseK = pi * (cutoff - fLow[k]) / (fHigh[k] - fLow[k])
        if filter_type = 1
            fH0Cut[k] = 0.5 * (1 + cos(phaseK))
        else
            fH0Cut[k] = 0.5 * (1 - cos(phaseK))
        endif
        if cutoff < lowestEdge
            lowestEdge = cutoff
        endif
    endif

    if resonance > 0
        if resonance_mode = 1
            gainCutK = fH0Cut[k] * (1 + resonance)
        else
            gainCutK = 1 + resonance
        endif
        if gainCutK < gainCutMin
            gainCutMin = gainCutK
        endif
        if gainCutK > gainCutMax
            gainCutMax = gainCutK
        endif
    endif
endfor

# --- Window / frequency resolution warning, from the EFFECTIVE window
#     and the lowest edge actually used ---
cyclesInWindow = lowestEdge * window_size_s
if cyclesInWindow < 3
    appendInfoLine: "  WARNING: the ", fixed$(window_size_s * 1000, 0), " ms window holds only ",
    ... fixed$(cyclesInWindow, 1), " cycles at ", round(lowestEdge), " Hz,"
    appendInfoLine: "           the lowest filter edge in this sweep. Frequency resolution is",
    ... " about ", fixed$(1 / window_size_s, 0), " Hz, so the edge cannot be placed"
    appendInfoLine: "           accurately there. Use a longer window (Smooth) for low sweeps."
endif

if filter_type = 3
    appendInfoLine: "Bandwidth: ", round(bandwidth), " Hz"
endif

if resonance > 0
    if resonance_mode = 1
        appendInfoLine: "Gaussian emphasis: ", fixed$(resonance, 2), " (width ",
        ... round(resonance_bandwidth), " Hz, multiplied into the response)"
        if filter_type < 3
            appendInfoLine: "  Gain AT the cutoff: ", fixed$(gainCutMin, 2), " to ",
            ... fixed$(gainCutMax, 2), " against a passband of 1.00."
            appendInfoLine: "  The lowpass/highpass response is at or below 0.5 there, so this"
            appendInfoLine: "  only exceeds the passband once Resonance passes 1.0."
            appendInfoLine: "  Set Resonance_mode to ""True peak at cutoff"" for a real peak."
        endif
    else
        appendInfoLine: "Gaussian emphasis: ", fixed$(resonance, 2), " (width ",
        ... round(resonance_bandwidth), " Hz, true peak at cutoff)"
        if filter_type < 3
            appendInfoLine: "  Gain AT the cutoff: ", fixed$(1 + resonance, 2),
            ... " against a passband of 1.00, and the peak is centred there."
        endif
    endif
    appendInfoLine: "  (This is the height of a Gaussian bump, not a filter Q or a pole.)"
endif
appendInfoLine: ""

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Adaptive Filter##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.30, "half",
        ... originalName$ + "  |  " + preset$ + "  |  " + filterType$
        ... + "  |  " + curve$ + "  |  " + quality$ + " window"

    # === FILTER SWEEP DISPLAY ===
    Select outer viewport: 0, 8, 0.6, 3.9
    Select inner viewport: 0.6, 7.7, 0.7, 3.7

    minFreqDisplay = 20
    maxFreqDisplay = min(nyquist, 12000)

    Axes: 0, duration, minFreqDisplay, maxFreqDisplay
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, duration, minFreqDisplay, maxFreqDisplay

    # Shade the passband and the transition bands from the SAME arrays
    # the audio uses, so this panel is a picture of the filter that ran.
    for k from 1 to nSegs
        segStart = (k - 1) * hopDur - padDur
        segEnd = segStart + window_size_s
        d1 = max(0, segStart)
        d2 = min(duration, segEnd)
        if d2 > d1
            if filter_type = 1
                Paint rectangle: "{0.85, 0.92, 1.0}", d1, d2, minFreqDisplay,
                ... max(minFreqDisplay, min(fLow[k], maxFreqDisplay))
                Paint rectangle: "{0.92, 0.95, 1.0}", d1, d2,
                ... max(minFreqDisplay, min(fLow[k], maxFreqDisplay)),
                ... max(minFreqDisplay, min(fHigh[k], maxFreqDisplay))
            elsif filter_type = 2
                Paint rectangle: "{0.85, 0.92, 1.0}", d1, d2,
                ... max(minFreqDisplay, min(fHigh[k], maxFreqDisplay)), maxFreqDisplay
                Paint rectangle: "{0.92, 0.95, 1.0}", d1, d2,
                ... max(minFreqDisplay, min(fLow[k], maxFreqDisplay)),
                ... max(minFreqDisplay, min(fHigh[k], maxFreqDisplay))
            else
                Paint rectangle: "{0.92, 0.95, 1.0}", d1, d2,
                ... max(minFreqDisplay, min(fLow[k], maxFreqDisplay)),
                ... max(minFreqDisplay, min(fHigh[k], maxFreqDisplay))
                Paint rectangle: "{0.85, 0.92, 1.0}", d1, d2,
                ... max(minFreqDisplay, min(fBpLow[k], maxFreqDisplay)),
                ... max(minFreqDisplay, min(fBpHigh[k], maxFreqDisplay))
            endif
        endif
    endfor

    # Cutoff line, drawn frame to frame
    Colour: "{0.80, 0.20, 0.20}"
    Line width: 2
    # Every frame whose WINDOW overlaps the file, with the plotted x
    # clamped into range. v1.1 required the window CENTRE to fall inside
    # [0, duration], so when the length was not a multiple of the hop the
    # shading ran to the end frequency while the line stopped short of it.
    prevSet = 0
    for k from 1 to nSegs
        segStartC = (k - 1) * hopDur - padDur
        segEndC = segStartC + window_size_s
        if segEndC > 0 and segStartC < duration
            plotX = min(max(segStartC + window_size_s / 2, 0), duration)
            if prevSet = 1
                Draw line: prevT, prevF, plotX, fCut[k]
            endif
            prevT = plotX
            prevF = fCut[k]
            prevSet = 1
        endif
    endfor
    Line width: 1

    # Transition edges
    Colour: "{0.60, 0.60, 0.90}"
    Dotted line
    prevSet = 0
    for k from 1 to nSegs
        segStartC = (k - 1) * hopDur - padDur
        segEndC = segStartC + window_size_s
        if segEndC > 0 and segStartC < duration
            plotX = min(max(segStartC + window_size_s / 2, 0), duration)
            if filter_type = 3
                loEdge = fBpLow[k]
                hiEdge = fBpHigh[k]
            else
                loEdge = fLow[k]
                hiEdge = fHigh[k]
            endif
            if prevSet = 1
                Draw line: prevT2, prevLo, plotX, loEdge
                Draw line: prevT2, prevHi, plotX, hiEdge
            endif
            prevT2 = plotX
            prevLo = loEdge
            prevHi = hiEdge
            prevSet = 1
        endif
    endfor
    Solid line

    # Emphasis marker: labelled for what it is, not as Q
    if resonance > 0
        Colour: "{0.90, 0.60, 0.20}"
        Font size: 7
        if resonance_mode = 1
            Text: duration * 0.98, "right", maxFreqDisplay * 0.94, "half",
            ... "Emphasis " + fixed$(resonance, 2) + " (multiplied)"
        else
            Text: duration * 0.98, "right", maxFreqDisplay * 0.94, "half",
            ... "Emphasis " + fixed$(resonance, 2) + " (peak at cutoff)"
        endif
    endif

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    Marks left every: 1, 2000, "yes", "yes", "no"

    Colour: "{0.20, 0.20, 0.80}"
    Font size: 7
    Text: duration * 0.02, "left", fCut[1], "half", string$(round(fCut[1])) + " Hz"
    Text: duration * 0.98, "right", fCut[nSegs], "half", string$(round(fCut[nSegs])) + " Hz"

    # === SUMMARY ===
    Select outer viewport: 0, 8, 3.95, 4.75
    Select inner viewport: 0.6, 7.7, 4.00, 4.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if output_level_mode = 1
        levelStr$ = "none"
    elsif output_level_mode = 2
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2)
    else
        levelStr$ = "normalize to " + fixed$(ceiling_peak, 2)
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
        ... "Sweep: " + string$(round(start_frequency)) + " -> " + string$(round(end_frequency)) + " Hz"
        ... + "  |  Curve: " + curve$
        ... + "  |  Window: " + fixed$(window_size_s * 1000, 0) + " ms (" + quality$ + ")"
        ... + "  |  Hop: " + fixed$(hopDur * 1000, 0) + " ms"
        ... + "  |  Frames: " + string$(nSegs)
    if filter_type = 3
        bandStr$ = "  |  Band: " + string$(round(fBpLow[1])) + "-" + string$(round(fBpHigh[1])) +
        ... " Hz -> " + string$(round(fBpLow[nSegs])) + "-" + string$(round(fBpHigh[nSegs])) + " Hz"
    else
        bandStr$ = "  |  Transition: +/- 15% of cutoff (min 50 Hz)"
    endif
    if resonance > 0
        emphStr$ = "  |  Emphasis: " + fixed$(resonance, 2) + " / " +
        ... string$(round(resonance_bandwidth)) + " Hz"
    else
        emphStr$ = "  |  Emphasis: off"
    endif
    Text: 0.02, "left", 0.18, "half",
        ... "Filter: " + filterType$
        ... + bandStr$
        ... + emphStr$
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
        ... + "  |  Level: " + levelStr$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# WORK COPY: time domain normalized to 0
# ============================================================
# v1.0 read only the duration and then extracted from time 0, which is
# wrong for any Sound whose xmin is not 0 (an Extract part with
# "Preserve times" produces exactly that).
selectObject: sound
workSound = Copy: "af_work"
Shift times to: "start time", 0

# ============================================================
# PADDED INPUT AND WINDOW-WEIGHT BUFFER
# ============================================================
# Built with Concatenate, which follows OBJECT-LIST order, so the three
# parts are created in the order they must join.

procedure buildPadded: .src
    Create Sound from formula: "pad_head", 1, 0, padDur, sampleRate, "0"
    .head = selected("Sound")
    selectObject: .src
    .mid = Copy: "pad_mid"
    Create Sound from formula: "pad_tail", 1, 0, padTailDur, sampleRate, "0"
    .tail = selected("Sound")
    selectObject: .head
    plusObject: .mid
    plusObject: .tail
    Concatenate
    .out = selected("Sound")
    removeObject: .head, .mid, .tail
    selectObject: .out
endproc

# Sample counts, not float durations. The concatenated buffer holds
# headNs + coreNs + tailNs samples, and every other buffer has to match
# that exactly or the frame offsets drift by a sample.
Create Sound from formula: "pad_probe", 1, 0, padDur, sampleRate, "0"
padProbe = selected("Sound")
padOffSamples = Get number of samples
removeObject: padProbe

Create Sound from formula: "tail_probe", 1, 0, padTailDur, sampleRate, "0"
tailProbe = selected("Sound")
tailSamples = Get number of samples
removeObject: tailProbe

selectObject: workSound
coreSamples = Get number of samples

paddedSamples = padOffSamples + coreSamples + tailSamples
paddedDur = paddedSamples / sampleRate

# --- Window weights ---
# Derived by running Extract part with the same window over a constant
# 1 signal, so the weights are exactly what Praat applies to the audio,
# with exactly the same sample count per frame.
Create Sound from formula: "ones_src", 1, 0, paddedDur, sampleRate, "1"
onesSrc = selected("Sound")

Create Sound from formula: "weight_buf", 1, 0, paddedDur, sampleRate, "0"
weightBuf = selected("Sound")

appendInfoLine: "Accumulating window weights..."

for k from 1 to nSegs
    segStart = (k - 1) * hopDur
    segEnd = segStart + window_size_s
    if segEnd > paddedDur
        segEnd = paddedDur
    endif
    if segEnd > segStart
        selectObject: onesSrc
        Extract part: segStart, segEnd, "Hanning", 1, "no"
        winSeg = selected("Sound")
        winNs = Get number of samples

        # Integer indices. "Get sample number from time" returns a REAL
        # (882.5 and the like), and an index inside object[...] is
        # rounded, so v1.0 could start a frame one sample off - and
        # inconsistently, since frame 1 was forced to index 1.
        startIdx = round(segStart * sampleRate) + 1
        if startIdx < 1
            startIdx = 1
        endif
        endIdx = startIdx + winNs - 1
        if endIdx > paddedSamples
            endIdx = paddedSamples
        endif
        frameStart[k] = startIdx
        frameEnd[k] = endIdx
        frameNs[k] = winNs

        if endIdx >= startIdx
            off = startIdx - 1
            t1 = (startIdx - 0.75) / sampleRate
            t2 = (endIdx - 0.25) / sampleRate
            selectObject: weightBuf
            Formula (part): t1, t2, 1, 1,
                ... "self + object[" + string$(winSeg) + ", 1, col - " + string$(off) + "]"
        endif
        removeObject: winSeg
    else
        frameStart[k] = 1
        frameEnd[k] = 0
        frameNs[k] = 0
    endif
endfor

removeObject: onesSrc

# ============================================================
# FILTER FORMULA FOR ONE FRAME
# ============================================================
procedure filterSpectrum: .k
    .cut$ = string$(fCut[.k])
    .low$ = string$(fLow[.k])
    .high$ = string$(fHigh[.k])
    .res$ = string$(resonance)
    .bw$ = string$(resonance_bandwidth)
    .g$ = "exp(-((x - " + .cut$ + ")/" + .bw$ + ")^2)"

    if filter_type = 1
        # === LOWPASS ===
        .roll$ = "0.5 * (1 + cos(pi * (x - " + .low$ + ") / (" + .high$ + " - " + .low$ + ")))"
        if resonance <= 0
            Formula: "if x < " + .low$ + " then self else if x > " + .high$ +
                ... " then 0 else self * " + .roll$ + " endif endif"
        elsif resonance_mode = 1
            .emph$ = "(1 + " + .res$ + " * " + .g$ + ")"
            Formula: "if x > " + .high$ + " then 0 else if x < " + .low$ +
                ... " then self * " + .emph$ + " else self * " + .emph$ + " * " + .roll$ +
                ... " endif endif"
        else
            # H(f) = H0(f) + ((1 + R) - H0(f)) * G(f)
            # At the cutoff G = 1, so H = 1 + R exactly, whatever H0 is
            # there - which matters, because H0 is only 0.5 when neither
            # bound was clamped. And since G'(cutoff) = 0, the H0 terms
            # cancel in H', so the maximum sits ON the cutoff.
            # v1.1 used H0 + (0.5 + R) * G, which hits the right VALUE
            # at the cutoff but leaves H'(cutoff) = H0'(cutoff) <> 0, so
            # the peak drifted into the passband: 200 Hz cutoff with
            # R = 0.8 peaked at 1.957 near 180.3 Hz, not 1.800 at 200.
            .peak$ = string$(1 + resonance)
            Formula: "if x < " + .low$ + " then self * (1 + " + .res$ + " * " + .g$ +
                ... ") else if x > " + .high$ + " then self * (" + .peak$ + " * " + .g$ +
                ... ") else self * ((" + .roll$ + ") + (" + .peak$ + " - (" + .roll$ +
                ... ")) * " + .g$ + ") endif endif"
        endif

    elsif filter_type = 2
        # === HIGHPASS ===
        .roll$ = "0.5 * (1 - cos(pi * (x - " + .low$ + ") / (" + .high$ + " - " + .low$ + ")))"
        if resonance <= 0
            Formula: "if x > " + .high$ + " then self else if x < " + .low$ +
                ... " then 0 else self * " + .roll$ + " endif endif"
        elsif resonance_mode = 1
            .emph$ = "(1 + " + .res$ + " * " + .g$ + ")"
            Formula: "if x < " + .low$ + " then 0 else if x > " + .high$ +
                ... " then self * " + .emph$ + " else self * " + .emph$ + " * " + .roll$ +
                ... " endif endif"
        else
            # Same construction as lowpass: H0 + ((1 + R) - H0) * G.
            .peak$ = string$(1 + resonance)
            Formula: "if x > " + .high$ + " then self * (1 + " + .res$ + " * " + .g$ +
                ... ") else if x < " + .low$ + " then self * (" + .peak$ + " * " + .g$ +
                ... ") else self * ((" + .roll$ + ") + (" + .peak$ + " - (" + .roll$ +
                ... ")) * " + .g$ + ") endif endif"
        endif

    else
        # === BANDPASS ===
        # Each transition uses its own measured width, so an edge that
        # was clamped to 0 Hz or to Nyquist still reaches 1 at the
        # passband. v1.0 divided both by the unclamped smoothing.
        .bpLow$ = string$(fBpLow[.k])
        .bpHigh$ = string$(fBpHigh[.k])
        .loW$ = string$(max(fLoWidth[.k], 1e-9))
        .hiW$ = string$(max(fHiWidth[.k], 1e-9))
        .loRoll$ = "0.5 * (1 - cos(pi * (x - " + .low$ + ") / " + .loW$ + "))"
        .hiRoll$ = "0.5 * (1 + cos(pi * (x - " + .bpHigh$ + ") / " + .hiW$ + "))"

        if resonance <= 0
            Formula: "if x < " + .low$ + " then 0 else if x > " + .high$ +
                ... " then 0 else if x < " + .bpLow$ + " then self * " + .loRoll$ +
                ... " else if x > " + .bpHigh$ + " then self * " + .hiRoll$ +
                ... " else self endif endif endif endif"
        else
            .emph$ = "(1 + " + .res$ + " * " + .g$ + ")"
            Formula: "if x < " + .low$ + " then 0 else if x > " + .high$ +
                ... " then 0 else if x < " + .bpLow$ + " then self * " + .emph$ + " * " +
                ... .loRoll$ + " else if x > " + .bpHigh$ + " then self * " + .emph$ + " * " +
                ... .hiRoll$ + " else self * " + .emph$ + " endif endif endif endif"
        endif
    endif
endproc

# ============================================================
# PROCESS ONE CHANNEL (weighted overlap-add)
# ============================================================
procedure processChannel: .inputSound
    @buildPadded: .inputSound
    .padded = buildPadded.out

    Create Sound from formula: "output_buffer", 1, 0, paddedDur, sampleRate, "0"
    .output = selected("Sound")

    for seg from 1 to nSegs
        if frameNs[seg] > 0
            .segStart = (seg - 1) * hopDur
            .segEnd = .segStart + window_size_s
            if .segEnd > paddedDur
                .segEnd = paddedDur
            endif

            selectObject: .padded
            .seg = Extract part: .segStart, .segEnd, "Hanning", 1, "no"
            .spec = To Spectrum: "yes"

            selectObject: .spec
            @filterSpectrum: seg

            To Sound
            .segFilt = selected("Sound")
            removeObject: .seg, .spec

            .startIdx = frameStart[seg]
            .endIdx = frameEnd[seg]
            if .endIdx >= .startIdx
                .off = .startIdx - 1
                .t1 = (.startIdx - 0.75) / sampleRate
                .t2 = (.endIdx - 0.25) / sampleRate
                selectObject: .output
                Formula (part): .t1, .t2, 1, 1,
                    ... "self + object[" + string$(.segFilt) + ", 1, col - " + string$(.off) + "]"
            endif
            removeObject: .segFilt
        endif

        if seg mod 50 = 0
            appendInfo: "."
        endif
    endfor

    removeObject: .padded

    # Divide out the accumulated window weight. Without this the Hanning
    # window is applied once per frame and never undone, which is the
    # fade-in and fade-out v1.0 produced at the file edges.
    selectObject: .output
    Formula: "if object[" + string$(weightBuf) + ", 1, col] > 0.000001 then self / object[" +
        ... string$(weightBuf) + ", 1, col] else 0 endif"

    # Cut the original span back out of the padded buffer
    .cutStart = padOffSamples / sampleRate
    .cutEnd = (padOffSamples + coreSamples) / sampleRate
    selectObject: .output
    Extract part: .cutStart, .cutEnd, "rectangular", 1, "no"
    .trimmed = selected("Sound")
    removeObject: .output

    selectObject: .trimmed
endproc

appendInfoLine: "Processing ", nSegs, " frames per channel..."

# ============================================================
# MAIN PROCESSING
# ============================================================
# Every channel is filtered and every channel is kept. v1.1 warned that
# channels 3 and up would be dropped and then dropped them, because any
# non-mono input took a hard-coded two-channel branch. A warning is not
# a safeguard against silently destroying four of six channels.
if numChannels = 1
    selectObject: workSound
    inputMono = Copy: "input_mono"
    @processChannel: inputMono
    finalOutput = selected("Sound")
    removeObject: inputMono
    appendInfoLine: ""
else
    for ch from 1 to numChannels
        selectObject: workSound
        Extract one channel: ch
        chIn[ch] = selected("Sound")
        appendInfo: "ch", ch
        @processChannel: chIn[ch]
        chOut[ch] = selected("Sound")
        removeObject: chIn[ch]
        appendInfoLine: ""
    endfor

    # Assemble by writing each filtered channel into its own row. This
    # takes any channel count, unlike Combine to stereo.
    selectObject: chOut[1]
    outSamples = Get number of samples
    outDurWork = Get total duration
    Create Sound from formula: "af_multi", numChannels, 0, outDurWork, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to numChannels
        selectObject: finalOutput
        Formula (part): 0, outDurWork, ch, ch,
            ... "object[" + string$(chOut[ch]) + ", 1, col]"
    endfor
    for ch from 1 to numChannels
        removeObject: chOut[ch]
    endfor
endif

removeObject: weightBuf, workSound

appendInfoLine: "Done."

# ============================================================
# FINALIZE
# ============================================================
selectObject: finalOutput

# Put the result back where the source lived
if srcStart <> 0
    Shift times to: "start time", srcStart
endif

pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

if output_level_mode = 2
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

Rename: originalName$ + "_" + filterType$ + "_" + quality$
finalName$ = selected$("Sound")

selectObject: finalOutput
out_peak = Get absolute extremum: 0, 0, "None"
out_dur = Get total duration

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Filter: ", filterType$
appendInfoLine: "Sweep: ", round(start_frequency), " -> ", round(end_frequency), " Hz (", curve$, ")"
appendInfoLine: "Duration: ", fixed$(out_dur, 4), " s (source ", fixed$(duration, 4), " s)"
appendInfoLine: "Peak before output stage: ", fixed$(pre_level_peak, 4)
if output_level_mode = 1
    appendInfoLine: "Output stage: none"
elsif output_level_mode = 2
    appendInfoLine: "Output stage: safety ceiling ", fixed$(ceiling_peak, 2), " - ", level_action$
else
    appendInfoLine: "Output stage: peak normalize to ", fixed$(ceiling_peak, 2),
    ... " (x", fixed$(level_gain, 4), ")"
    appendInfoLine: "  NOTE: this restores the level the filter removed, so presets are no"
    appendInfoLine: "        longer comparable by loudness."
endif
if output_level_mode <> 3 and out_peak > 1
    appendInfoLine: "WARNING: output peak exceeds 1.0 and will clip when saved to integer PCM."
endif

if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput
