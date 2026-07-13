# ============================================================
# Praat AudioTools - Subtle_Random_Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Subtle Random Texture — spectral coloring with smooth random
#   resonances.  Creates organic shimmer, formant-like coloring,
#   or evolving timbral shifts.
#
#   v1.0 rewrote the DSP:
#   - OLD: per-bin independent random gain = sounded like noise
#   - NEW: smooth random spectral envelope (sum of Gaussians at
#     random centre frequencies) = sounds like resonance coloring.
#     Processed as N full-file FFT copies with different random
#     parameters per segment, then blended with triangular weights
#     that form a perfect partition of unity.
#
#   v1.2 (2026):
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only form with a hand-tuned negative offset is the
#     margin-compression collision geometry).
#   - Inputs with more than 2 channels get an info NOTE that
#     channels 3+ are not processed (L/R only).
#   - AUDIT: verified correct as written -- the triangular-blend
#     partition of unity (measured: evolving-mode unity residual
#     -240 dB), the phase-preserving spectral gain, per-channel
#     stereo with independent decorrelating draws, and the
#     row-aware wet/dry with channel-mismatch fallback.
#
#   v1.1 improves the visualization to show the phenomenon honestly:
#   - Stores every segment's resonance set (not just the last).
#   - Overlays all time_segments gain curves with a dark-to-light
#     gradient, so the user sees HOW MUCH the spectrum drifts.
#   - Labels the stereo case: only the left channel's curves are
#     plotted (the right channel is independently randomised for
#     decorrelation; this is by design).
#   - Warns when time_segments x duration x channels is large.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-
#   Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Subtle Random Texture v1.2
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer (gentle spectral coloring)
        option Warm Resonance (formant-like)
        option Evolving Texture (slow spectral drift)
        option Lo-Fi Character (narrow peaks)
        option Spectral Chorus (dense, wide)
        option Frozen Colour (static, no time variation)
    comment === Resonance Parameters ===
    natural Number_of_resonances 8
    positive Bandwidth_Hz 100
    positive Depth 2.0
    comment (0.5 = subtle, 2.0 = clear, 5.0 = extreme)
    comment === Frequency Range ===
    positive Low_freq_Hz 80
    positive High_freq_Hz 10000
    comment === Time Variation ===
    natural Time_segments 4
    comment (1 = static, 4-8 = evolving shimmer)
    comment === Mix ===
    real Wet_dry_percent 100
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply presets ===
presetName$ = "Custom"

if preset = 2
    # Subtle Shimmer — the gentlest audible coloring
    number_of_resonances = 6
    bandwidth_Hz = 150
    depth = 1.0
    low_freq_Hz = 200
    high_freq_Hz = 10000
    time_segments = 6
    presetName$ = "SubtleShimmer"
elsif preset = 3
    # Warm Resonance — strong formant character
    number_of_resonances = 6
    bandwidth_Hz = 80
    depth = 2.5
    low_freq_Hz = 150
    high_freq_Hz = 5000
    time_segments = 3
    presetName$ = "WarmResonance"
elsif preset = 4
    # Evolving Texture — dramatic spectral drift
    number_of_resonances = 10
    bandwidth_Hz = 100
    depth = 2.0
    low_freq_Hz = 100
    high_freq_Hz = 10000
    time_segments = 8
    presetName$ = "EvolvingTexture"
elsif preset = 5
    # Lo-Fi Character — extreme narrow peaks, very gritty
    number_of_resonances = 8
    bandwidth_Hz = 40
    depth = 4.0
    low_freq_Hz = 200
    high_freq_Hz = 6000
    time_segments = 4
    presetName$ = "LoFiCharacter"
elsif preset = 6
    # Spectral Chorus — dense coloring across full spectrum
    number_of_resonances = 16
    bandwidth_Hz = 200
    depth = 1.5
    low_freq_Hz = 80
    high_freq_Hz = 14000
    time_segments = 6
    presetName$ = "SpectralChorus"
elsif preset = 7
    # Frozen Colour — static, strong resonant filter
    number_of_resonances = 8
    bandwidth_Hz = 60
    depth = 3.0
    low_freq_Hz = 100
    high_freq_Hz = 10000
    time_segments = 1
    presetName$ = "FrozenColour"
endif

# === Input check ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels
nyquist = original_sr / 2

if high_freq_Hz > nyquist - 100
    high_freq_Hz = nyquist - 100
endif
if low_freq_Hz >= high_freq_Hz
    low_freq_Hz = 80
endif

clearinfo
writeInfoLine: "=== Subtle Random Texture v1.2 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Resonances: ", number_of_resonances
appendInfoLine: "Bandwidth: ", bandwidth_Hz, " Hz"
appendInfoLine: "Depth: ", fixed$(depth, 2)
appendInfoLine: "Freq range: ", low_freq_Hz, " - ", high_freq_Hz, " Hz"
appendInfoLine: "Time segments: ", time_segments
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"

# Rough memory/CPU warning. Each segment requires a full-file FFT
# round-trip plus a resident copy of the result in RAM until blend.
# For very long sources with many segments and stereo, this adds up.
fftCopies = time_segments * n_channels
if fftCopies * duration > 120
    appendInfoLine: ""
    appendInfoLine: "  (heads-up: ", fftCopies,
        ... " full-file FFT copies x ", fixed$(duration, 1),
        ... " s = heavy run; reduce time_segments if slow)"
endif
appendInfoLine: ""

# ── Counters and storage for per-segment resonance parameters ──
# applyRandomResonances uses storeSeg to decide WHERE in the 2D
# store to write its draws. We store only LEFT-channel calls so
# the visualization has a coherent set of curves to overlay; for
# stereo the RIGHT channel gets its own independent draws (by
# design, for decorrelation) but those are not plotted.
storeSeg = 0
storeCapSeg = time_segments
# Per-segment, per-resonance store. Accessed as allResFC[seg, r].
# In Praat, indexed-variable syntax creates these on first write,
# but we "touch" them here so the visualization can't hit an
# uninitialized read when e.g. the user chose depth=0.
for s from 1 to storeCapSeg
    for r from 1 to number_of_resonances
        allResFC[s, r]  = 0
        allResAmp[s, r] = 0
    endfor
endfor

# ============================================================
# PROCEDURE: Apply smooth random spectral envelope
# ============================================================
#
# Smooth gain curve as a sum of Gaussian peaks/dips at random
# centre frequencies.  Sounds like natural room resonances.
#
# gain(f) = 1 + SUM_r[ amp_r * exp( -((f - fc_r) / bw)^2 ) ]
#
# Built as a single Formula string — one pass over the Spectrum.

procedure applyRandomResonances: .spectrumID
    selectObject: .spectrumID

    # max(0.05, ...) prevents polarity inversion at extreme depth
    .formula$ = "self * max(0.05, 1.0"

    for .r from 1 to number_of_resonances
        .fc = randomUniform(low_freq_Hz, high_freq_Hz)
        # Alternate sign: odd = boost, even = cut
        if .r mod 2 = 1
            .sign = 1
        else
            .sign = -1
        endif
        .amp = depth * .sign * randomUniform(0.5, 1.0)

        # Keep a 1D copy for the per-call debug line just below.
        resFC[.r]  = .fc
        resAmp[.r] = .amp

        # Persist into the 2D store so the visualization can plot
        # every segment's curve. Only the first N=storeCapSeg calls
        # (i.e. the left-channel segment sequence) are stored.
        if storeSeg >= 1 and storeSeg <= storeCapSeg
            allResFC[storeSeg, .r]  = .fc
            allResAmp[storeSeg, .r] = .amp
        endif

        .formula$ = .formula$
            ... + " + " + fixed$(.amp, 4)
            ... + " * exp(-((x - " + fixed$(.fc, 1)
            ... + ") / " + fixed$(bandwidth_Hz, 1) + ")^2)"
    endfor

    .formula$ = .formula$ + ")"

    selectObject: .spectrumID
    Formula: .formula$

    # Debug: show resonance params and peak dB effect
    .dbgLine$ = "    Resonances:"
    .maxBoost = 0
    .maxCut = 0
    for .r from 1 to number_of_resonances
        if resAmp[.r] > 0
            .dbgLine$ = .dbgLine$ + " +" + fixed$(resAmp[.r], 2) + "@" + fixed$(resFC[.r], 0)
            if resAmp[.r] > .maxBoost
                .maxBoost = resAmp[.r]
            endif
        else
            .dbgLine$ = .dbgLine$ + " " + fixed$(resAmp[.r], 2) + "@" + fixed$(resFC[.r], 0)
            if -resAmp[.r] > .maxCut
                .maxCut = -resAmp[.r]
            endif
        endif
    endfor
    appendInfoLine: .dbgLine$
    .boostDB = 20 * log10(1 + .maxBoost)
    .cutGain = max(0.05, 1 - .maxCut)
    .cutDB = 20 * log10(.cutGain)
    appendInfoLine: "    Peak effect: +" + fixed$(.boostDB, 1) + " dB boost, "
        ... + fixed$(.cutDB, 1) + " dB cut"
endproc

# ============================================================
# MAIN PROCESSING
#
# Architecture (v1.1 fix):
#   For time_segments=1: single full-file FFT → modify → iFFT
#     (perfect reconstruction, zero artifacts)
#   For time_segments≥2: create N full-file processed copies,
#     each with DIFFERENT random resonances, then crossfade
#     between them using triangular weights that sum to 1.0 at
#     every point.  No windowed extraction, no OLA, no COLA
#     issues.  Each copy is a complete, properly reconstructed
#     signal.  The time variation comes purely from the
#     crossfade blend, not from segmented analysis.
# ============================================================

procedure processOneChannel: .inputChannelID
    selectObject: .inputChannelID
    .chDur = Get total duration
    .chSR = Get sampling frequency

    if time_segments <= 1
        # ---- STATIC: single FFT round-trip (perfect reconstruction) ----
        appendInfoLine: "  Static mode — single FFT..."
        selectObject: .inputChannelID
        Copy: "ch_work"
        .chCopy = selected("Sound")
        To Spectrum: "yes"
        .spec = selected("Spectrum")
        storeSeg = storeSeg + 1
        @applyRandomResonances: .spec

        selectObject: .spec
        To Sound
        .wetResult = selected("Sound")
        removeObject: .spec

        # Trim FFT padding
        selectObject: .wetResult
        .rDur = Get total duration
        if .rDur > .chDur
            Extract part: 0, .chDur, "rectangular", 1, "no"
            .trimmed = selected("Sound")
            removeObject: .wetResult
            .wetResult = .trimmed
        endif

        removeObject: .chCopy

    else
        # ---- EVOLVING: crossfade-blend of N full-file copies ----
        appendInfoLine: "  Evolving mode — ", time_segments, " full-file copies..."

        # Step 1: create N processed copies (each = full FFT round-trip
        # with different random resonances)
        for .seg from 1 to time_segments
            selectObject: .inputChannelID
            Copy: "seg_work"
            .segCopy = selected("Sound")
            To Spectrum: "yes"
            .segSpec = selected("Spectrum")
            storeSeg = storeSeg + 1
            @applyRandomResonances: .segSpec

            selectObject: .segSpec
            To Sound
            .segResult = selected("Sound")
            removeObject: .segSpec, .segCopy

            # Trim FFT padding
            selectObject: .segResult
            .rDur = Get total duration
            if .rDur > .chDur
                Extract part: 0, .chDur, "rectangular", 1, "no"
                .trimmed = selected("Sound")
                removeObject: .segResult
                .segResult = .trimmed
            endif

            processedCopy[.seg] = .segResult
            appendInfoLine: "    Copy ", .seg, " of ", time_segments, " done"
        endfor

        # Step 2: blend copies using triangular weights that sum to 1.0
        #
        # For N copies, centre[k] = (k-1)/(N-1) * duration
        # hop = duration / (N-1)
        # weight_k(t) = max(0, 1 - |t - centre_k| / hop)
        #
        # At any time t, exactly two adjacent weights overlap and
        # sum to 1.0 (triangular COLA at hop = width/2).

        Create Sound from formula: "blend_output", 1, 0, .chDur, .chSR, "0"
        .wetResult = selected("Sound")

        if time_segments = 2
            # Special case: linear crossfade from copy 1 to copy 2
            .id1$ = string$(processedCopy[1])
            .id2$ = string$(processedCopy[2])
            .durStr$ = fixed$(.chDur, 10)
            selectObject: .wetResult
            Formula: "object[" + .id1$ + ", col] * (1 - x/" + .durStr$ + ")"
                ... + " + object[" + .id2$ + ", col] * (x/" + .durStr$ + ")"
        else
            # General case: N≥3, triangular weight per copy
            .hop = .chDur / (time_segments - 1)
            .hopStr$ = fixed$(.hop, 10)

            for .seg from 1 to time_segments
                .centre = (.seg - 1) * .hop
                .centreStr$ = fixed$(.centre, 10)
                .copyStr$ = string$(processedCopy[.seg])

                selectObject: .wetResult
                Formula: "self + object[" + .copyStr$ + ", col]"
                    ... + " * max(0, 1 - abs(x - " + .centreStr$ + ") / " + .hopStr$ + ")"
            endfor
        endif

        # Cleanup copies
        for .seg from 1 to time_segments
            removeObject: processedCopy[.seg]
        endfor
    endif

    # Store result ID for caller
    processOneChannel.result = .wetResult
endproc

# ============================================================
# PROCESS CHANNELS
# ============================================================

appendInfoLine: ""

if n_channels >= 2
    # ---- STEREO: process each channel independently ----
    if n_channels > 2
        appendInfoLine: "NOTE: input has ", n_channels, " channels; only 1-2 (L/R) are processed."
    endif
    appendInfoLine: "Processing LEFT channel..."
    selectObject: originalID
    Extract one channel: 1
    chL_input = selected("Sound")
    @processOneChannel: chL_input
    wetL = processOneChannel.result
    removeObject: chL_input

    # Park the store counter past its cap so the right channel's
    # applyRandomResonances calls don't overwrite the stored L data.
    storeSeg = storeCapSeg + 1

    appendInfoLine: "Processing RIGHT channel..."
    selectObject: originalID
    Extract one channel: 2
    chR_input = selected("Sound")
    @processOneChannel: chR_input
    wetR = processOneChannel.result
    removeObject: chR_input

    # Combine
    selectObject: wetL
    plusObject: wetR
    Combine to stereo
    wetSound = selected("Sound")
    removeObject: wetL, wetR

else
    # ---- MONO ----
    appendInfoLine: "Processing mono..."
    selectObject: originalID
    Copy: "mono_input"
    monoInput = selected("Sound")
    @processOneChannel: monoInput
    wetSound = processOneChannel.result
    removeObject: monoInput
endif

# ============================================================
# WET/DRY MIX
# ============================================================

if dry_level > 0
    appendInfoLine: "Mixing wet/dry..."
    origStr$ = string$(originalID)
    selectObject: wetSound
    wetNch = Get number of channels
    selectObject: originalID
    origNch = Get number of channels

    if wetNch = origNch
        selectObject: wetSound
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + origStr$ + ", row, col] * " + string$(dry_level)
    else
        # Channel mismatch: mix per channel with mono original
        selectObject: originalID
        if origNch > 1
            origMix = Convert to mono
        else
            origMix = Copy: "origMix"
        endif
        origMixStr$ = string$(origMix)
        selectObject: wetSound
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + origMixStr$ + ", col] * " + string$(dry_level)
        removeObject: origMix
    endif
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: wetSound
Scale peak: scale_peak

# Debug: final levels
selectObject: originalID
dbg_inRMS = Get root-mean-square: 0, 0
selectObject: wetSound
dbg_outRMS = Get root-mean-square: 0, 0
appendInfoLine: ""
appendInfoLine: "[DEBUG] Input RMS: ", fixed$(dbg_inRMS, 4),
    ... "  Output RMS: ", fixed$(dbg_outRMS, 4),
    ... "  Ratio: ", fixed$(dbg_outRMS / (dbg_inRMS + 1e-10), 4)
Rename: originalName$ + "_" + presetName$
resultID = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Select inner viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Subtle Random Texture v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.24, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + string$(number_of_resonances) + " resonances"
        ... + "  |  depth=" + fixed$(depth, 2)

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: originalID
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: resultID
    Colour: "{0.35, 0.58, 0.72}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Spectral gain curves — ALL segments overlaid
    # Dark → light gradient shows progression segment 1..N.
    # For stereo, only the LEFT channel's curves are plotted;
    # the right channel has its own independent random draws
    # (by design, for decorrelation) and is not shown.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.24, 3.54
    Select inner viewport: 0.55, 7.65, 2.34, 3.44

    # Axis range
    gainMin = max(0, 1.0 - depth * 1.1)
    gainMax = 1.0 + depth * 1.1
    if gainMax < 2.0
        gainMax = 2.0
    endif

    Axes: 0, high_freq_Hz * 1.1, gainMin, gainMax
    Paint rectangle: "{0.96, 0.96, 0.96}",
        ... 0, high_freq_Hz * 1.1, gainMin, gainMax

    # Unity line
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 1, high_freq_Hz * 1.1, 1

    # Clamp floor line
    Colour: "{0.90, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0.05, high_freq_Hz * 1.1, 0.05
    Solid line

    # ---- Draw each stored segment's gain curve, dark to light ----
    nPlotPts = 300
    freqStep = high_freq_Hz / nPlotPts

    # For each segment s, compute its curve and draw with a colour
    # that darkens with segment index. Older segments are muted blue
    # (r=0.10, g=0.25, b=0.55); newer segments pale blue
    # (r=0.55, g=0.70, b=0.90). When storeCapSeg=1 the curve is
    # drawn with the "newest" colour for consistency.
    for s from 1 to storeCapSeg
        if storeCapSeg > 1
            t01 = (s - 1) / (storeCapSeg - 1)
        else
            t01 = 1
        endif
        rCol = 0.10 + 0.45 * t01
        gCol = 0.25 + 0.45 * t01
        bCol = 0.55 + 0.35 * t01
        Colour: "{" + fixed$(rCol, 2) + "," + fixed$(gCol, 2) + "," + fixed$(bCol, 2) + "}"

        # Last segment drawn more prominently
        if s = storeCapSeg
            Line width: 2.2
        else
            Line width: 1.2
        endif

        prevFreq = 0
        prevGain = 1
        for pt from 1 to nPlotPts
            freq = (pt - 0.5) * freqStep
            gainVal = 1.0
            for r from 1 to number_of_resonances
                gainVal = gainVal + allResAmp[s, r]
                    ... * exp(-((freq - allResFC[s, r]) / bandwidth_Hz)^2)
            endfor
            if gainVal < 0.05
                gainVal = 0.05
            endif
            if pt > 1
                Draw line: prevFreq, prevGain, freq, gainVal
            endif
            prevFreq = freq
            prevGain = gainVal
        endfor
    endfor
    Line width: 1

    # ---- Resonance-centre ticks for the LAST segment only ----
    # (Showing ticks for all segments turns the panel into a dot
    # storm; the ticks should help read the curve in focus, which
    # is the heavy line = last segment.)
    for r from 1 to number_of_resonances
        fcLast = allResFC[storeCapSeg, r]
        ampLast = allResAmp[storeCapSeg, r]
        if fcLast > 0 and fcLast <= high_freq_Hz
            tickY = 1.0 + ampLast
            if tickY < 0.05
                tickY = 0.05
            endif
            if ampLast > 0
                Paint circle (mm): "{0.22, 0.65, 0.32}", fcLast, tickY, 1.2
            else
                Paint circle (mm): "{0.75, 0.30, 0.30}", fcLast, tickY, 1.2
            endif
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"

    # Panel title reflects how many curves are shown + stereo caveat
    if time_segments = 1
        envTitle$ = "Spectral envelope  (green = boost, red = cut)"
    else
        envTitle$ = "Spectral envelope  ("
            ... + string$(time_segments)
            ... + " curves overlaid, dark=first  light=last;"
            ... + " ticks mark last curve)"
    endif
    if n_channels >= 2
        envTitle$ = envTitle$ + "  [L channel]"
    endif
    Text top: "no", envTitle$

    # ----------------------------------------------------------
    # Output spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.62, 4.82
    Select inner viewport: 0.55, 7.65, 3.70, 4.74
    selectObject: resultID
    nChRes = Get number of channels
    if nChRes > 1
        Extract one channel: 1
        vizSpec = selected("Sound")
    else
        Copy: "vizSpec"
        vizSpec = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, vizSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    if time_segments > 1
        Text top: "no", "Output spectrogram  (" + string$(time_segments) + " evolving segments)"
    else
        Text top: "no", "Output spectrogram  (static)"
    endif

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.92, 5.62
    Select inner viewport: 0.55, 7.65, 4.98, 5.56
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.48, "half",
        ... "Preset: " + presetName$
        ... + "  |  Resonances: " + string$(number_of_resonances)
        ... + "  |  BW: " + string$(bandwidth_Hz) + " Hz"
        ... + "  |  Depth: " + fixed$(depth, 2)
        ... + "  |  Range: " + string$(low_freq_Hz) + "-" + string$(high_freq_Hz) + " Hz"
    Text: 0.02, "left", 0.18, "half",
        ... "Segments: " + string$(time_segments)
        ... + "  |  Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
        ... + "  |  SR: " + string$(original_sr) + " Hz"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID
