# ============================================================
# Praat AudioTools - Adaptive_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Visualization correctness + response panel
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
# Changelog v1.4 (2026):
#   - VISUALIZATION ONLY; audio processing, analysis, synthesis,
#     object-management and output behaviour are byte-for-byte unchanged.
#   - Drawing-frame fix. Praat derives a panel's inner margins from the
#     CURRENT font size, so "Font size" issued AFTER "Select inner
#     viewport" silently re-derives a wider frame. v1.3 did this in the
#     title strip and in the plot, so the shading, the cutoff line and
#     the left-hand ticks were all drawn to a frame about 0.37 in wider
#     than the axis box that was drawn around them: the plot sat outside
#     its own border. Every panel now sets the font first and re-issues
#     "Select inner viewport" + "Axes" between drawing groups.
#   - The time axis exists. v1.3 labelled the x axis "Time (s)" and drew
#     no bottom marks at all, so no point in the sweep could be read off
#     the picture. Marks are drawn on both axes with a step snapped to
#     1/2/5 x 10^k, and frequency ticks are written with own labels so
#     12000 reads "12k" instead of Praat's "1.2*10^4".
#   - Endpoint labels land on their line ends. v1.3 wrote them after
#     "Draw inner box" and "Marks left", which leave the drawing frame on
#     the outer viewport, displacing the labels ~0.1 in.
#   - The display range follows the sweep. v1.3 capped the axis at
#     12 kHz; "Draw line" does not clip, so any sweep above that drew its
#     cutoff across the panels below. The range is taken from the frame
#     table (including the emphasis skirt) and every plotted value is
#     clamped as well.
#   - The summary border encloses the summary. It was drawn on a stale
#     frame, ~0.06 in wide of the grey strip on every side.
#   - NEW: the trajectory is drawn over a spectrogram of the input, so
#     the sweep can be read against the material it sweeps over.
#   - NEW: a response panel showing the actual gain curve at the start,
#     middle and end of the sweep, with the gain AT the cutoff marked.
#     The transition width, and whether the Gaussian emphasis is a peak
#     or a dip below the passband, are invisible in a trajectory plot;
#     this is the panel where Resonance_mode can be seen to do anything.
#     @resp mirrors @filterSpectrum branch for branch - a change to one
#     has to be made in the other.
#   - Object names are escaped before drawing: _ ^ # % are markup in
#     Picture text, so a Sound called "take_2" lost its underscore.
#   - The page is filled. v1.3 declared an 8.00 in page and stopped
#     drawing at 4.75 in, exporting 40% of the sheet blank.
#
# Changelog v1.3 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
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

form Adaptive Filter v1.4
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
writeInfoLine: "=== Adaptive Filter v1.4 ==="
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
# VISUALIZATION HELPERS
# ============================================================
# A tick step of span/N prints labels like 657 / 1314 / 1971.
# Snap it to 1, 2 or 5 x 10^k so an axis reads in round numbers.
procedure niceStep: .span, .target
    .raw = .span / .target
    if .raw <= 0
        .step = 1
    else
        .mag = 10 ^ floor(log10(.raw))
        .n = .raw / .mag
        if .n < 1.5
            .step = .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endif
endproc

# Praat writes 12000 as 1.2*10^4 on an axis. Own labels avoid that.
procedure hzLabel: .v
    if .v >= 1000
        .out$ = fixed$(.v / 1000, 1)
        .out$ = replace$(.out$, ".0", "", 0) + "k"
    else
        .out$ = fixed$(.v, 0)
    endif
endproc

# _ ^ # % are markup in Picture text and are SWALLOWED, so an object
# name like "take_2" loses its underscore and everything after "#" goes
# bold. Escape them before any name reaches a Text command.
procedure sanitize: .s$
    .out$ = replace$(.s$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

# The filter response at one frequency, for one frame. This mirrors
# @filterSpectrum branch for branch: the response panel has to be the
# curve the audio is actually multiplied by, not an idealised drawing
# of one. Any future change to @filterSpectrum has to be made here too.
procedure resp: .k, .f
    .cut = fCut[.k]
    .low = fLow[.k]
    .high = fHigh[.k]
    .g = 0
    if resonance > 0
        .g = exp(-((.f - .cut) / resonance_bandwidth) ^ 2)
    endif
    .emph = 1 + resonance * .g
    .peak = 1 + resonance

    if filter_type = 1
        .roll = 0.5 * (1 + cos(pi * (.f - .low) / (.high - .low)))
        if resonance <= 0
            if .f < .low
                .out = 1
            elsif .f > .high
                .out = 0
            else
                .out = .roll
            endif
        elsif resonance_mode = 1
            if .f > .high
                .out = 0
            elsif .f < .low
                .out = .emph
            else
                .out = .emph * .roll
            endif
        else
            if .f < .low
                .out = .emph
            elsif .f > .high
                .out = .peak * .g
            else
                .out = .roll + (.peak - .roll) * .g
            endif
        endif

    elsif filter_type = 2
        .roll = 0.5 * (1 - cos(pi * (.f - .low) / (.high - .low)))
        if resonance <= 0
            if .f > .high
                .out = 1
            elsif .f < .low
                .out = 0
            else
                .out = .roll
            endif
        elsif resonance_mode = 1
            if .f < .low
                .out = 0
            elsif .f > .high
                .out = .emph
            else
                .out = .emph * .roll
            endif
        else
            if .f > .high
                .out = .emph
            elsif .f < .low
                .out = .peak * .g
            else
                .out = .roll + (.peak - .roll) * .g
            endif
        endif

    else
        .bpLow = fBpLow[.k]
        .bpHigh = fBpHigh[.k]
        .loW = max(fLoWidth[.k], 1e-9)
        .hiW = max(fHiWidth[.k], 1e-9)
        .loRoll = 0.5 * (1 - cos(pi * (.f - .low) / .loW))
        .hiRoll = 0.5 * (1 + cos(pi * (.f - .bpHigh) / .hiW))
        if .f < .low or .f > .high
            .out = 0
        elsif .f < .bpLow
            .out = .loRoll
        elsif .f > .bpHigh
            .out = .hiRoll
        else
            .out = 1
        endif
        if resonance > 0
            .out = .out * .emph
        endif
    endif
endproc

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    # --- Display range, derived from the frames that will actually run.
    # v1.3 hard-capped the axis at 12 kHz, and "Draw line" does not clip,
    # so a sweep above that drew its cutoff straight across the summary
    # panel. The range follows the data now and every plotted value is
    # clamped into it as well.
    minFreqDisplay = 0
    topEdge = 0
    for k from 1 to nSegs
        if fHigh[k] > topEdge
            topEdge = fHigh[k]
        endif
        if resonance > 0
            resTop = fCut[k] + 2.5 * resonance_bandwidth
            if resTop > topEdge
                topEdge = resTop
            endif
        endif
    endfor
    maxFreqDisplay = min(nyquist, topEdge * 1.15)
    maxFreqDisplay = max(maxFreqDisplay, 500)

    # Frames whose window overlaps the file at all
    kFirst = 0
    kLast = 1
    for k from 1 to nSegs
        vSegStart = (k - 1) * hopDur - padDur
        if vSegStart + window_size_s > 0 and vSegStart < duration
            if kFirst = 0
                kFirst = k
            endif
            kLast = k
        endif
    endfor
    if kFirst = 0
        kFirst = 1
    endif
    kMid = round((kFirst + kLast) / 2)

    @sanitize: originalName$
    vizName$ = sanitize.out$
    @sanitize: preset$
    vizPreset$ = sanitize.out$

    # --- Spectrogram of the input, as the backdrop for the trajectory.
    # A swept cutoff only means something against the material it is
    # sweeping over: this is what tells the user whether the filter
    # crosses their partials or misses them entirely.
    selectObject: sound
    vizMono = Copy: "af_vizmono"
    if numChannels > 1
        Convert to mono
        vizMonoTmp = selected("Sound")
        removeObject: vizMono
        vizMono = vizMonoTmp
    endif
    selectObject: vizMono
    Shift times to: "start time", 0
    vizWin = min(0.03, duration / 4)
    vizWin = max(vizWin, 0.005)
    vizStep = max(duration / 900, 0.0005)
    vizSpec = To Spectrogram: vizWin, maxFreqDisplay, vizStep, 20, "Gaussian"

    # === TITLE ===
    # Font size BEFORE the viewport selection. Praat derives the inner
    # viewport margins from the CURRENT font, so a font change made after
    # the selection silently re-derives a wider frame and shifts every
    # following Text and Draw outward - which is what pushed the v1.3
    # plot outside its own axis box.
    Font size: 12
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Adaptive Filter v1.4##"

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + vizPreset$ +
    ... " | " + filterType$ + " | " + curve$

    # ============================================================
    # PANEL 1 - filter trajectory over the input spectrogram
    # ============================================================
    Font size: 7
    Select outer viewport: 0, 8, 0.60, 3.70
    Select inner viewport: 0.60, 7.70, 0.85, 3.40
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay

    # A Spectrogram's own domain is inset by half its analysis window, so
    # Paint leaves a bare sliver at each end of the panel. Filling first
    # makes that read as panel background instead of blank page.
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, duration, minFreqDisplay, maxFreqDisplay

    selectObject: vizSpec
    Paint: 0, duration, minFreqDisplay, maxFreqDisplay, 100, "yes", 42, 6, 0, "no"

    # Paint leaves the axes on the spectrogram's own domain, so the
    # panel geometry is re-established before anything is overlaid.
    Select inner viewport: 0.60, 7.70, 0.85, 3.40
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay

    # Transition edges first, so the cutoff line sits on top of them
    # Dashed at width 1.5 rather than a dotted hairline: over a
    # spectrogram a 1 px dotted line is barely visible, and Praat's
    # on-screen renderer drops sub-pixel dashes altogether even though
    # they survive a 300-dpi export.
    Colour: "{0.10, 0.35, 0.75}"
    Line width: 1.5
    Dashed line
    prevSet = 0
    for k from 1 to nSegs
        vSegStart = (k - 1) * hopDur - padDur
        if vSegStart + window_size_s > 0 and vSegStart < duration
            plotX = min(max(vSegStart + window_size_s / 2, 0), duration)
            if filter_type = 3
                loEdge = fBpLow[k]
                hiEdge = fBpHigh[k]
            else
                loEdge = fLow[k]
                hiEdge = fHigh[k]
            endif
            loEdge = min(max(loEdge, minFreqDisplay), maxFreqDisplay)
            hiEdge = min(max(hiEdge, minFreqDisplay), maxFreqDisplay)
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

    # Cutoff / centre frequency
    Colour: "{0.80, 0.20, 0.20}"
    Line width: 2.5
    prevSet = 0
    for k from 1 to nSegs
        vSegStart = (k - 1) * hopDur - padDur
        if vSegStart + window_size_s > 0 and vSegStart < duration
            plotX = min(max(vSegStart + window_size_s / 2, 0), duration)
            plotF = min(max(fCut[k], minFreqDisplay), maxFreqDisplay)
            if prevSet = 1
                Draw line: prevT, prevF, plotX, plotF
            endif
            prevT = plotX
            prevF = plotF
            prevSet = 1
        endif
    endfor
    Line width: 1

    # Endpoint readouts. In v1.3 these were written after Draw inner box
    # and Marks left, both of which leave the drawing frame on the OUTER
    # viewport, so the labels landed about 0.1 in outside the panel and
    # sat visibly off their own line ends.
    Select inner viewport: 0.60, 7.70, 0.85, 3.40
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay
    @hzLabel: round(fCut[kFirst])
    startLab$ = hzLabel.out$
    @hzLabel: round(fCut[kLast])
    endLab$ = hzLabel.out$
    labY1 = min(max(fCut[kFirst], minFreqDisplay), maxFreqDisplay)
    labY2 = min(max(fCut[kLast], minFreqDisplay), maxFreqDisplay)
    labH = (maxFreqDisplay - minFreqDisplay) * 0.055
    # Red on a mid-grey spectrogram is marginal and on a dark band it is
    # unreadable, so each readout gets its own patch to sit on.
    labY1 = min(labY1, maxFreqDisplay - labH)
    labY2 = min(labY2, maxFreqDisplay - labH)
    Paint rectangle: "White", duration * 0.008, duration * 0.115,
    ... labY1 + labH * 0.10, labY1 + labH
    Paint rectangle: "White", duration * 0.885, duration * 0.992,
    ... labY2 + labH * 0.10, labY2 + labH

    Select inner viewport: 0.60, 7.70, 0.85, 3.40
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay
    Colour: "{0.80, 0.20, 0.20}"
    Text: duration * 0.015, "left", labY1 + labH * 0.10, "bottom", startLab$ + " Hz"
    Text: duration * 0.985, "right", labY2 + labH * 0.10, "bottom", endLab$ + " Hz"

    # Frame, ticks and axis labels last, on a freshly re-established frame
    Select inner viewport: 0.60, 7.70, 0.85, 3.40
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay
    Colour: "Black"
    Line width: 1
    Draw inner box

    @niceStep: duration, 8
    tStep = niceStep.step
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    @niceStep: maxFreqDisplay, 6
    fStep = niceStep.step
    One mark left: 0, "no", "yes", "no", "0"
    mk = fStep
    while mk < maxFreqDisplay * 0.999
        @hzLabel: mk
        One mark left: mk, "no", "yes", "no", hzLabel.out$
        mk = mk + fStep
    endwhile
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # === LEGEND ===
    # Its own strip rather than a floating label inside the panel: over a
    # spectrogram there is no reliable patch of background to write on.
    Font size: 6
    Select outer viewport: 0, 8, 3.80, 4.14
    Select inner viewport: 0.60, 7.70, 3.88, 4.06
    Axes: 0, 1, 0, 1
    Colour: "{0.80, 0.20, 0.20}"
    Line width: 2
    Draw line: 0.005, 0.5, 0.045, 0.5
    Line width: 1
    Colour: "{0.10, 0.35, 0.75}"
    Line width: 1.5
    Dashed line
    Draw line: 0.235, 0.5, 0.275, 0.5
    Solid line
    Line width: 1

    Select inner viewport: 0.60, 7.70, 3.88, 4.06
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    if filter_type = 3
        Text: 0.055, "left", 0.5, "half", "band centre"
        Text: 0.285, "left", 0.5, "half", "passband edges"
    else
        Text: 0.055, "left", 0.5, "half", "cutoff"
        Text: 0.285, "left", 0.5, "half", "transition band edges"
    endif
    Text: 0.60, "left", 0.5, "half", "backdrop: input spectrogram (42 dB range)"

    # ============================================================
    # PANEL 2 - the response the audio is actually multiplied by
    # ============================================================
    # v1.3 drew where the filter was but never what it did. Everything
    # that is easy to get wrong here - how wide the transition is, and
    # whether the Gaussian emphasis is a peak or a dip below the passband
    # - is invisible in a trajectory plot and obvious in this one.
    nPts = 600
    maxH = 1
    for j from 0 to nPts
        fj = minFreqDisplay + (maxFreqDisplay - minFreqDisplay) * j / nPts
        vizF[j] = fj
        @resp: kFirst, fj
        rA[j] = resp.out
        @resp: kMid, fj
        rB[j] = resp.out
        @resp: kLast, fj
        rC[j] = resp.out
        maxH = max(maxH, max(rA[j], max(rB[j], rC[j])))
    endfor
    yTop = max(1.15, maxH * 1.12)

    Font size: 7
    Select outer viewport: 0, 8, 4.20, 6.60
    Select inner viewport: 0.60, 7.70, 4.45, 6.35
    Axes: 0, maxFreqDisplay, 0, yTop
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, maxFreqDisplay, 0, yTop

    # Unity reference: the passband level everything is judged against
    Select inner viewport: 0.60, 7.70, 4.45, 6.35
    Axes: 0, maxFreqDisplay, 0, yTop
    Colour: "{0.65, 0.65, 0.65}"
    Dashed line
    Draw line: 0, 1, maxFreqDisplay, 1
    Solid line

    # Three snapshots along the sweep, coloured start -> end so they read
    # against the trajectory above (the end curve shares the cutoff red)
    for c from 1 to 3
        if c = 1
            Colour: "{0.20, 0.40, 0.80}"
            kk = kFirst
        elsif c = 2
            Colour: "{0.55, 0.30, 0.60}"
            kk = kMid
        else
            Colour: "{0.80, 0.20, 0.20}"
            kk = kLast
        endif
        Select inner viewport: 0.60, 7.70, 4.45, 6.35
        Axes: 0, maxFreqDisplay, 0, yTop
        Line width: 1.5
        for j from 1 to nPts
            if c = 1
                y0 = rA[j - 1]
                y1 = rA[j]
            elsif c = 2
                y0 = rB[j - 1]
                y1 = rB[j]
            else
                y0 = rC[j - 1]
                y1 = rC[j]
            endif
            Draw line: vizF[j - 1], min(y0, yTop), vizF[j], min(y1, yTop)
        endfor
        Line width: 1
        # Mark the gain at the cutoff itself
        gc = fH0Cut[kk]
        if resonance > 0
            if resonance_mode = 1
                gc = fH0Cut[kk] * (1 + resonance)
            else
                gc = 1 + resonance
            endif
        endif
        if fCut[kk] <= maxFreqDisplay and gc <= yTop
            Paint circle (mm): "{0.20, 0.20, 0.20}", fCut[kk], gc, 1.1
        endif
    endfor

    # yTop is 12% above the highest point any curve reaches, so this band
    # is guaranteed clear whatever the sweep does. A right-hand stack
    # would sit on the curves themselves for a rising highpass.
    @hzLabel: round(fCut[kFirst])
    lab1$ = hzLabel.out$
    @hzLabel: round(fCut[kMid])
    lab2$ = hzLabel.out$
    @hzLabel: round(fCut[kLast])
    lab3$ = hzLabel.out$

    Font size: 6
    Select inner viewport: 0.60, 7.70, 4.45, 6.35
    Axes: 0, maxFreqDisplay, 0, yTop
    Colour: "{0.20, 0.40, 0.80}"
    Text: maxFreqDisplay * 0.02, "left", yTop * 0.95, "half", "start " + lab1$ + " Hz"
    Colour: "{0.55, 0.30, 0.60}"
    Text: maxFreqDisplay * 0.20, "left", yTop * 0.95, "half", "middle " + lab2$ + " Hz"
    Colour: "{0.80, 0.20, 0.20}"
    Text: maxFreqDisplay * 0.38, "left", yTop * 0.95, "half", "end " + lab3$ + " Hz"
    Colour: "{0.28, 0.28, 0.28}"
    Text: maxFreqDisplay * 0.99, "right", yTop * 0.95, "half",
    ... "dots mark the gain at each cutoff"

    Font size: 7
    Select inner viewport: 0.60, 7.70, 4.45, 6.35
    Axes: 0, maxFreqDisplay, 0, yTop
    Colour: "Black"
    Line width: 1
    Draw inner box
    @niceStep: yTop, 4
    yStep = niceStep.step
    Marks left every: 1, yStep, "yes", "yes", "no"
    One mark bottom: 0, "no", "yes", "no", "0"
    mk = fStep
    while mk < maxFreqDisplay * 0.999
        @hzLabel: mk
        One mark bottom: mk, "no", "yes", "no", hzLabel.out$
        mk = mk + fStep
    endwhile
    Text left: "yes", "Gain (linear)"
    Text bottom: "yes", "Frequency (Hz)"

    # === SUMMARY ===
    Font size: 7
    Select outer viewport: 0, 8, 6.75, 7.80
    Select inner viewport: 0.60, 7.70, 6.95, 7.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if output_level_mode = 1
        levelStr$ = "none"
    elsif output_level_mode = 2
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2)
    else
        levelStr$ = "normalize to " + fixed$(ceiling_peak, 2)
    endif
    if filter_type = 3
        @hzLabel: round(fBpLow[kFirst])
        b1$ = hzLabel.out$
        @hzLabel: round(fBpHigh[kFirst])
        b2$ = hzLabel.out$
        @hzLabel: round(fBpLow[kLast])
        b3$ = hzLabel.out$
        @hzLabel: round(fBpHigh[kLast])
        b4$ = hzLabel.out$
        bandStr$ = "  |  Band: " + b1$ + "-" + b2$ + " -> " + b3$ + "-" + b4$ + " Hz"
    else
        bandStr$ = "  |  Transition: +/- 15\%  of cutoff (min 50 Hz)"
    endif
    if resonance > 0
        if resonance_mode = 1
            emphStr$ = "  |  Emphasis: " + fixed$(resonance, 2) + " / " +
            ... string$(round(resonance_bandwidth)) + " Hz (multiplied)"
        else
            emphStr$ = "  |  Emphasis: " + fixed$(resonance, 2) + " / " +
            ... string$(round(resonance_bandwidth)) + " Hz (peak at cutoff)"
        endif
    else
        emphStr$ = "  |  Emphasis: off"
    endif

    Select inner viewport: 0.60, 7.70, 6.95, 7.65
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"

    Font size: 6
    Select inner viewport: 0.60, 7.70, 6.95, 7.65
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
    ... "Sweep: " + string$(round(start_frequency)) + " -> " + string$(round(end_frequency)) + " Hz"
    ... + "  |  Curve: " + curve$
    ... + "  |  Window: " + fixed$(window_size_s * 1000, 0) + " ms (" + quality$ + ")"
    ... + "  |  Hop: " + fixed$(hopDur * 1000, 0) + " ms"
    ... + "  |  Frames: " + string$(nSegs)
    Text: 0.02, "left", 0.18, "half",
    ... "Filter: " + filterType$
    ... + bandStr$
    ... + emphStr$
    ... + "  |  Duration: " + fixed$(duration, 2) + " s"
    ... + "  |  Level: " + levelStr$

    # The grey strip is framed with Draw rectangle on a re-established
    # frame. v1.3 called it straight after the Text commands, which leave
    # the frame on the outer viewport, so the border was drawn about
    # 0.06 in wide of the fill it was supposed to enclose.
    Select inner viewport: 0.60, 7.70, 6.95, 7.65
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizSpec, vizMono

    # Restore the complete page. "Save as ... PNG" and the Picture
    # window's own Save/Copy export the CURRENT viewport selection, so
    # ending on the summary strip would export only the summary strip.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
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