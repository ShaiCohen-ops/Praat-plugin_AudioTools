# ============================================================
# Praat AudioTools - Subtle_Random_Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Subtle Random Texture — per-copy phase-preserving spectral
#   colouring with smooth random Gaussian gain features. Creates organic
#   shimmer, formant-like colouring, or evolving timbral shifts.
#   In evolving mode, several static full-file FFT colourations are
#   blended in time with triangular weights that sum to unity.
#
#   v1.0 rewrote the DSP:
#   - OLD: per-bin independent random gain = sounded like noise
#   - NEW: smooth random spectral envelope (sum of Gaussians at
#     random centre frequencies) = sounds like resonance coloring.
#     Processed as N full-file FFT copies with different random
#     parameters per segment, then blended with triangular weights
#     that form a perfect partition of unity.
#
#   v1.3.1 (2026):
#   - VIZ: standardized Picture width/height and 2x2 panel geometry
#     to the AudioTools house layout used by Spectral Swirl and
#     Stepped Notch Filter. DSP is unchanged.
#   - VIZ: compressed the process law to one isolated strip and
#     standardized title/panel/summary typography.
#
#   v1.3 (2026):
#   - AUDIT: wet=0 is now a true dry bypass (no peak scaling).
#   - AUDIT: >2-channel input is rejected instead of silently
#     discarding channels 3+.
#   - DOC: frequency range is explicitly the random CENTRE range;
#     Gaussian tails may extend outside it.
#   - VIZ: mechanism-first 2x2 layout: actual random envelopes,
#     exact triangular blend weights, realized gain trajectories,
#     and measured pure-wet spectral consequence.
#   - VIZ: all frequency plots use logarithmic frequency and
#     measured/calculated ranges; no theoretical-average random plot.
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

form Subtle Random Texture v1.3.1
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
    comment === Resonance-centre Range ===
    positive Low_freq_Hz 80
    positive High_freq_Hz 10000
    comment (Gaussian tails may extend outside the centre range)
    comment === Time Variation ===
    natural Time_segments 4
    comment (1 = static, 4-8 = evolving shimmer)
    comment === Mix ===
    comment (Stereo input: L/R receive independent random envelopes)
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

if n_channels > 2
    exitScript: "Subtle Random Texture currently supports mono or stereo input. This version will not discard channels 3+."
endif

if nyquist <= 120
    exitScript: "Sampling rate is too low for the requested spectral texture."
endif

if high_freq_Hz > nyquist - 100
    high_freq_Hz = nyquist - 100
endif
if low_freq_Hz >= high_freq_Hz
    low_freq_Hz = max(20, 0.25 * high_freq_Hz)
endif

clearinfo
writeInfoLine: "=== Subtle Random Texture v1.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Resonances: ", number_of_resonances
appendInfoLine: "Bandwidth: ", bandwidth_Hz, " Hz"
appendInfoLine: "Depth: ", fixed$(depth, 2)
appendInfoLine: "Centre range: ", low_freq_Hz, " - ", high_freq_Hz, " Hz"
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
# Smooth, phase-preserving gain curve as a sum of Gaussian
# peaks/dips at random centre frequencies. This is spectral
# colouration, not a physical room-resonance model.
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
    appendInfoLine: "    Largest single feature: +" + fixed$(.boostDB, 1) + " dB boost, "
        ... + fixed$(.cutDB, 1) + " dB floor-limited cut"
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
        # ---- STATIC: single full-file FFT colouration ----
        appendInfoLine: "  Static mode — single full-file FFT colouration..."
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
# PURE-WET REFERENCE FOR MEASUREMENT
# ============================================================

if draw_visualization
    selectObject: wetSound
    Copy: "SRT_pure_wet_viz"
    vizWetID = selected("Sound")
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

if wet_level <= 0
    # True bypass: preserve the original samples and level exactly.
    removeObject: wetSound
    selectObject: originalID
    Copy: originalName$ + "_" + presetName$
    wetSound = selected("Sound")
else
    selectObject: wetSound
    Scale peak: scale_peak
    Rename: originalName$ + "_" + presetName$
endif
resultID = wetSound

# Debug: final levels
selectObject: originalID
dbg_inRMS = Get root-mean-square: 0, 0
selectObject: resultID
dbg_outRMS = Get root-mean-square: 0, 0
appendInfoLine: ""
appendInfoLine: "[QC] Input RMS: ", fixed$(dbg_inRMS, 4),
    ... "  Output RMS: ", fixed$(dbg_outRMS, 4),
    ... "  Ratio: ", fixed$(dbg_outRMS / (dbg_inRMS + 1e-10), 4)
if wet_level <= 0
    appendInfoLine: "[QC] Wet=0: true dry bypass; peak scaling skipped."
endif

# ============================================================
# VISUALIZATION — v1.3 mechanism-first layout
# ============================================================

if draw_visualization
    # ----------------------------------------------------------
    # Prepare representative channel objects. The stored random
    # envelope set is channel 1; for stereo, channel 2 has an
    # independent random realization by design.
    # ----------------------------------------------------------
    selectObject: originalID
    if n_channels > 1
        Extract one channel: 1
        vizSrc = selected("Sound")
    else
        Copy: "SRT_viz_source"
        vizSrc = selected("Sound")
    endif

    selectObject: vizWetID
    wetVizNch = Get number of channels
    if wetVizNch > 1
        Extract one channel: 1
        vizWet = selected("Sound")
    else
        Copy: "SRT_viz_wet"
        vizWet = selected("Sound")
    endif

    # ----------------------------------------------------------
    # Exact blend-unity QC: the same triangular laws used by DSP.
    # ----------------------------------------------------------
    unityMaxErr = 0
    if time_segments <= 1
        unityMaxErr = 0
    else
        for q from 0 to 100
            tq = duration * q / 100
            wsum = 0
            if time_segments = 2
                wsum = (1 - tq / duration) + (tq / duration)
            else
                qhop = duration / (time_segments - 1)
                for s from 1 to time_segments
                    qcentre = (s - 1) * qhop
                    wsum = wsum + max(0, 1 - abs(tq - qcentre) / qhop)
                endfor
            endif
            qerr = abs(wsum - 1)
            if qerr > unityMaxErr
                unityMaxErr = qerr
            endif
        endfor
    endif
    appendInfoLine: "[QC] Triangular blend max unity error: ", fixed$(unityMaxErr, 12)

    # ----------------------------------------------------------
    # Precompute ACTUAL stored envelope curves in dB on a log grid.
    # These are the exact random draws used for channel 1.
    # ----------------------------------------------------------
    vizFLo = max(50, low_freq_Hz * 0.6)
    vizFHi = min(nyquist * 0.97, high_freq_Hz * 1.25)
    if vizFHi <= vizFLo
        vizFLo = max(20, 0.1 * nyquist)
        vizFHi = 0.95 * nyquist
    endif
    logFLo = log10(vizFLo)
    logFHi = log10(vizFHi)
    envPts = 100
    envDbMinAll = 1e9
    envDbMaxAll = -1e9
    for p from 1 to envPts
        fracP = (p - 1) / (envPts - 1)
        lf = logFLo + fracP * (logFHi - logFLo)
        fHz = 10^lf
        envX[p] = lf
        localMin = 1e9
        localMax = -1e9
        for s from 1 to storeCapSeg
            g = 1
            for r from 1 to number_of_resonances
                g = g + allResAmp[s, r] * exp(-((fHz - allResFC[s, r]) / bandwidth_Hz)^2)
            endfor
            if g < 0.05
                g = 0.05
            endif
            gDb = 20 * log10(g)
            if s = 1
                envFirst[p] = gDb
            endif
            if s = storeCapSeg
                envLast[p] = gDb
            endif
            if gDb < localMin
                localMin = gDb
            endif
            if gDb > localMax
                localMax = gDb
            endif
        endfor
        envMin[p] = localMin
        envMax[p] = localMax
        if localMin < envDbMinAll
            envDbMinAll = localMin
        endif
        if localMax > envDbMaxAll
            envDbMaxAll = localMax
        endif
    endfor
    envAbs = max(abs(envDbMinAll), abs(envDbMaxAll))
    envY = max(6, 5 * ceiling(envAbs / 5))

    # ----------------------------------------------------------
    # Probe-frequency trajectories from the exact blend law.
    # Since every static FFT copy preserves phase, a stationary
    # component at f is multiplied by SUM_s w_s(t) G_s(f).
    # ----------------------------------------------------------
    probe1 = 10^(log10(low_freq_Hz) + 0.20 * (log10(high_freq_Hz) - log10(low_freq_Hz)))
    probe2 = 10^(log10(low_freq_Hz) + 0.50 * (log10(high_freq_Hz) - log10(low_freq_Hz)))
    probe3 = 10^(log10(low_freq_Hz) + 0.80 * (log10(high_freq_Hz) - log10(low_freq_Hz)))
    trajPts = 101
    trajMin = 1e9
    trajMax = -1e9
    for q from 1 to trajPts
        tq = duration * (q - 1) / (trajPts - 1)
        trajT[q] = tq
        for k from 1 to 3
            if k = 1
                pf = probe1
            elsif k = 2
                pf = probe2
            else
                pf = probe3
            endif
            effG = 0
            for s from 1 to storeCapSeg
                gs = 1
                for r from 1 to number_of_resonances
                    gs = gs + allResAmp[s, r] * exp(-((pf - allResFC[s, r]) / bandwidth_Hz)^2)
                endfor
                if gs < 0.05
                    gs = 0.05
                endif
                if time_segments <= 1
                    ws = 1
                elsif time_segments = 2
                    if s = 1
                        ws = 1 - tq / duration
                    else
                        ws = tq / duration
                    endif
                else
                    thop = duration / (time_segments - 1)
                    tc = (s - 1) * thop
                    ws = max(0, 1 - abs(tq - tc) / thop)
                endif
                effG = effG + ws * gs
            endfor
            effDb = 20 * log10(max(0.05, effG))
            trajDb[k, q] = effDb
            if effDb < trajMin
                trajMin = effDb
            endif
            if effDb > trajMax
                trajMax = effDb
            endif
        endfor
    endfor
    trajPad = max(2, 0.12 * (trajMax - trajMin + 1e-9))
    trajYMin = trajMin - trajPad
    trajYMax = trajMax + trajPad

    # ----------------------------------------------------------
    # Measured pure-wet spectral consequence using local LTAS
    # averages. This is a measurement, not a theoretical envelope.
    # ----------------------------------------------------------
    selectObject: vizSrc
    To Spectrum: "yes"
    srcSpecViz = selected("Spectrum")
    To Ltas (1-to-1)
    srcLtas = selected("Ltas")
    removeObject: srcSpecViz

    selectObject: vizWet
    To Spectrum: "yes"
    wetSpecViz = selected("Spectrum")
    To Ltas (1-to-1)
    wetLtas = selected("Ltas")
    removeObject: wetSpecViz

    measPts = 70
    srcMaxDb = -1e9
    for p from 1 to measPts
        fracP = (p - 1) / (measPts - 1)
        lf = logFLo + fracP * (logFHi - logFLo)
        fHz = 10^lf
        bwLo = max(1, fHz / 1.045)
        bwHi = min(nyquist, fHz * 1.045)
        selectObject: srcLtas
        sDb = Get mean: bwLo, bwHi, "dB"
        selectObject: wetLtas
        wDb = Get mean: bwLo, bwHi, "dB"
        measX[p] = lf
        measSrc[p] = sDb
        measDiff[p] = wDb - sDb
        if sDb > srcMaxDb
            srcMaxDb = sDb
        endif
    endfor
    measAbs = 0
    for p from 1 to measPts
        if measSrc[p] > srcMaxDb - 55
            if abs(measDiff[p]) > measAbs
                measAbs = abs(measDiff[p])
            endif
        endif
    endfor
    measY = max(3, 3 * ceiling(measAbs / 3))
    if measY > 30
        measY = 30
    endif

    # ----------------------------------------------------------
    # Picture layout — 2x2; one claim per panel.
    # ----------------------------------------------------------
    Erase all
    Select outer viewport: 0, 8.1, 0, 5.3

    # Title strip
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Select inner viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "Subtle Random Texture v1.3.1"
    Font size: 6.5
    Colour: "{0.35,0.35,0.35}"
    if n_channels = 2
        titleNote$ = presetName$ + "  |  channel 1 realization shown; R is independently randomized"
    else
        titleNote$ = presetName$ + "  |  actual random realization"
    endif
    Text: 0.5, "centre", 0.08, "half", titleNote$

    # Process strip
    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Select inner viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96,0.96,0.96}", 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.20,0.20,0.20}"
    Text: 0.5, "centre", 0.50, "half", "FFT copies -> phase-preserving random G_s(f) -> IFFT -> triangular blend;  sum w_s(t) = 1"

    # ---------- A: actual envelopes ----------
    Select outer viewport: 0.3, 3.95, 0.60, 2.60
    # title strip A
    Select outer viewport: 0.3, 3.95, 0.60, 0.88
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "A  ACTUAL RANDOM ENVELOPES"
    # plot A
    Select inner viewport: 0.72, 3.72, 1.02, 2.36
    Axes: logFLo, logFHi, -envY, envY
    Paint rectangle: "{0.97,0.97,0.97}", logFLo, logFHi, -envY, envY
    Colour: "{0.78,0.78,0.78}"
    Draw line: logFLo, 0, logFHi, 0
    # measured min/max range as vertical whiskers
    Line width: 1
    for p from 1 to envPts
        if p mod 3 = 1
            Colour: "{0.82,0.86,0.90}"
            Draw line: envX[p], envMin[p], envX[p], envMax[p]
        endif
    endfor
    # first curve
    Colour: "{0.45,0.45,0.45}"
    for p from 2 to envPts
        Draw line: envX[p-1], envFirst[p-1], envX[p], envFirst[p]
    endfor
    # last curve
    Colour: "{0.12,0.42,0.68}"
    Line width: 2
    for p from 2 to envPts
        Draw line: envX[p-1], envLast[p-1], envX[p], envLast[p]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max(3, envY/3), "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Gain (dB)"
    # Manual logarithmic frequency marks
    if vizFLo <= 50 and 50 <= vizFHi
        One mark bottom: log10(50), "no", "yes", "no", "50"
    endif
    if vizFLo <= 100 and 100 <= vizFHi
        One mark bottom: log10(100), "no", "yes", "no", "100"
    endif
    if vizFLo <= 200 and 200 <= vizFHi
        One mark bottom: log10(200), "no", "yes", "no", "200"
    endif
    if vizFLo <= 500 and 500 <= vizFHi
        One mark bottom: log10(500), "no", "yes", "no", "500"
    endif
    if vizFLo <= 1000 and 1000 <= vizFHi
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
    endif
    if vizFLo <= 2000 and 2000 <= vizFHi
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
    endif
    if vizFLo <= 5000 and 5000 <= vizFHi
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if vizFLo <= 10000 and 10000 <= vizFHi
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif
    if vizFLo <= 20000 and 20000 <= vizFHi
        One mark bottom: log10(20000), "no", "yes", "no", "20k"
    endif
    Text bottom: "yes", "Frequency (Hz, log)"
    # concise legend inside plot
    Font size: 6
    Colour: "{0.45,0.45,0.45}"
    Text: logFLo + 0.04*(logFHi-logFLo), "left", envY*0.82, "half", "first"
    Colour: "{0.12,0.42,0.68}"
    Text: logFLo + 0.18*(logFHi-logFLo), "left", envY*0.82, "half", "last"
    Colour: "{0.55,0.60,0.65}"
    Text: logFLo + 0.31*(logFHi-logFLo), "left", envY*0.82, "half", "range"

    # ---------- B: exact blend weights ----------
    Select outer viewport: 4.05, 7.75, 0.60, 2.60
    Select outer viewport: 4.05, 7.75, 0.60, 0.88
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "B  EXACT TIME BLEND"
    Select inner viewport: 4.46, 7.53, 1.02, 2.36
    Axes: 0, duration, 0, 1.08
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, 0, 1.08
    if time_segments <= 1
        Colour: "{0.12,0.42,0.68}"
        Line width: 2
        Draw line: 0, 1, duration, 1
    else
        # Individual triangular weights
        Line width: 1
        for s from 1 to time_segments
            Colour: "{0.68,0.72,0.76}"
            if time_segments = 2
                if s = 1
                    Draw line: 0, 1, duration, 0
                else
                    Draw line: 0, 0, duration, 1
                endif
            else
                bhop = duration / (time_segments - 1)
                bc = (s - 1) * bhop
                bL = max(0, bc - bhop)
                bR = min(duration, bc + bhop)
                if bc > 0
                    Draw line: bL, 0, bc, 1
                endif
                if bc < duration
                    Draw line: bc, 1, bR, 0
                endif
            endif
        endfor
        # Exact sum line sampled from the same law
        Colour: "{0.12,0.42,0.68}"
        Line width: 2
        prevT = 0
        prevS = 1
        for q from 1 to 100
            tq = duration * q / 100
            wsum = 0
            if time_segments = 2
                wsum = (1 - tq/duration) + tq/duration
            else
                bhop = duration / (time_segments - 1)
                for s from 1 to time_segments
                    bc = (s - 1) * bhop
                    wsum = wsum + max(0, 1 - abs(tq - bc) / bhop)
                endfor
            endif
            Draw line: prevT, prevS, tq, wsum
            prevT = tq
            prevS = wsum
        endfor
    endif
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, max(0.1, duration/4), "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Weight"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Text top: "no", "sum residual = " + fixed$(unityMaxErr, 12)

    # ---------- C: realized gain trajectories ----------
    Select outer viewport: 0.3, 3.95, 2.82, 4.82
    Select outer viewport: 0.3, 3.95, 2.82, 3.10
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "C  REALIZED GAIN OVER TIME"
    Select inner viewport: 0.72, 3.72, 3.22, 4.56
    Axes: 0, duration, trajYMin, trajYMax
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, trajYMin, trajYMax
    Colour: "{0.78,0.78,0.78}"
    if trajYMin < 0 and trajYMax > 0
        Draw line: 0, 0, duration, 0
    endif
    # 3 probe trajectories
    Colour: "{0.45,0.45,0.45}"
    for q from 2 to trajPts
        Draw line: trajT[q-1], trajDb[1,q-1], trajT[q], trajDb[1,q]
    endfor
    Colour: "{0.12,0.42,0.68}"
    Line width: 2
    for q from 2 to trajPts
        Draw line: trajT[q-1], trajDb[2,q-1], trajT[q], trajDb[2,q]
    endfor
    Line width: 1
    Colour: "{0.55,0.32,0.20}"
    for q from 2 to trajPts
        Draw line: trajT[q-1], trajDb[3,q-1], trajT[q], trajDb[3,q]
    endfor
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max(1, (trajYMax-trajYMin)/4), "yes", "yes", "no"
    Marks bottom every: 1, max(0.1, duration/4), "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Gain (dB)"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Colour: "{0.45,0.45,0.45}"
    Text: duration*0.03, "left", trajYMax - 0.10*(trajYMax-trajYMin), "half", fixed$(probe1,0)+" Hz"
    Colour: "{0.12,0.42,0.68}"
    Text: duration*0.25, "left", trajYMax - 0.10*(trajYMax-trajYMin), "half", fixed$(probe2,0)+" Hz"
    Colour: "{0.55,0.32,0.20}"
    Text: duration*0.47, "left", trajYMax - 0.10*(trajYMax-trajYMin), "half", fixed$(probe3,0)+" Hz"

    # ---------- D: measured pure-wet consequence ----------
    Select outer viewport: 4.05, 7.75, 2.82, 4.82
    Select outer viewport: 4.05, 7.75, 2.82, 3.10
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "D  MEASURED PURE-WET CHANGE"
    Select inner viewport: 4.46, 7.53, 3.22, 4.56
    Axes: logFLo, logFHi, -measY, measY
    Paint rectangle: "{0.97,0.97,0.97}", logFLo, logFHi, -measY, measY
    Colour: "{0.75,0.75,0.75}"
    Draw line: logFLo, 0, logFHi, 0
    Colour: "{0.12,0.42,0.68}"
    Line width: 1.5
    havePrev = 0
    for p from 1 to measPts
        if measSrc[p] > srcMaxDb - 55
            yy = measDiff[p]
            if yy > measY
                yy = measY
            elsif yy < -measY
                yy = -measY
            endif
            if havePrev
                Draw line: prevMX, prevMY, measX[p], yy
            endif
            prevMX = measX[p]
            prevMY = yy
            havePrev = 1
        else
            havePrev = 0
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max(3, measY/3), "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Wet - source (dB)"
    if vizFLo <= 50 and 50 <= vizFHi
        One mark bottom: log10(50), "no", "yes", "no", "50"
    endif
    if vizFLo <= 100 and 100 <= vizFHi
        One mark bottom: log10(100), "no", "yes", "no", "100"
    endif
    if vizFLo <= 200 and 200 <= vizFHi
        One mark bottom: log10(200), "no", "yes", "no", "200"
    endif
    if vizFLo <= 500 and 500 <= vizFHi
        One mark bottom: log10(500), "no", "yes", "no", "500"
    endif
    if vizFLo <= 1000 and 1000 <= vizFHi
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
    endif
    if vizFLo <= 2000 and 2000 <= vizFHi
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
    endif
    if vizFLo <= 5000 and 5000 <= vizFHi
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if vizFLo <= 10000 and 10000 <= vizFHi
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif
    if vizFLo <= 20000 and 20000 <= vizFHi
        One mark bottom: log10(20000), "no", "yes", "no", "20k"
    endif
    Text bottom: "yes", "Frequency (Hz, log)"
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text top: "no", "local LTAS averages; display capped at +/-" + fixed$(measY,0) + " dB"

    # Bottom summary strip
    Select outer viewport: 0.4, 7.7, 4.96, 5.22
    Select inner viewport: 0.4, 7.7, 4.96, 5.22
    Axes: 0,1,0,1
    Paint rectangle: "{0.94,0.94,0.94}", 0,1,0,1
    Font size: 6.3
    Colour: "{0.25,0.25,0.25}"
    Text: 0.5, "centre", 0.52, "half", "centres=" + fixed$(low_freq_Hz,0) + "-" + fixed$(high_freq_Hz,0) + " Hz  |  BW=" + fixed$(bandwidth_Hz,0) + " Hz  |  N=" + string$(number_of_resonances) + "  |  segments=" + string$(time_segments) + "  |  wet=" + fixed$(wet_dry_percent,0) + "%  |  RMS out/in=" + fixed$(dbg_outRMS/(dbg_inRMS+1e-10),2)

    # Restore defaults / cleanup visualization objects.
    Font size: 10
    Colour: "Black"
    Line width: 1
    removeObject: srcLtas, wetLtas, vizSrc, vizWet, vizWetID
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
