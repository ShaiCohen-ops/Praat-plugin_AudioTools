# ============================================================
# Praat AudioTools - Spectral Painter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2026) - verified transfer law, corrected mix, mechanism-first visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Whole-sound frequency-domain spectral painting.
#   Deterministic modes apply a real frequency-dependent mask to both
#   real and imaginary FFT components; negative mask values imply a pi
#   spectral polarity flip rather than attenuation.
#   Random Complex Diffusion independently perturbs the real and imaginary
#   FFT components per bin, producing both magnitude and phase/time diffusion.
#   Stereo input is processed channel-by-channel. Deterministic modes use the
#   same law in both channels; Random Complex Diffusion uses independent
#   realizations. Mono input can optionally widen only the wet path by 12 ms.
#   Supports mono and stereo Sounds.
#
# ============================================================

form Spectral Painter v0.7
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Broken Radio (hard spectral polarity steps)
        option Demon Voice (low-frequency weighting)
        option Glass Shatter (extreme complex-bin diffusion)
        option Black Hole (phase-inversion comb)
        option Bit Rot (stepped polarity corruption)
        option Insect Swarm (dense dual spectral comb)
        option Frozen Cathedral (log-spaced spectral ringing)
        option Dying Machine (sawtooth spectral bands)
        option Quantum Tunnel (near-beating spectral combs)
        option Vocal Destroyer (complex formant-band diffusion)
        option Thunder Rumble (existing low-frequency emphasis)
        option Crystal Fracture (fine stepped phase comb)
        option Toxic Waste (inverse complex-bin diffusion)
        option Ghost Signal (subtle spectral ripple)
        option Nuclear Meltdown (extreme complex-bin diffusion)
        option Cello: Spectral Phase Comb (fixed-frequency coloration)
        option Cello: Spectral Smear (complex-bin diffusion)
        option Cello: Body Resonance Warp (broad spectral sculpt)
    comment === MODULATION TYPE ===
    optionmenu Modulation_type: 1
        option Sine Wave (Linear)
        option Sine Wave (Logarithmic/Musical)
        option Triangle Wave
        option Square Wave (Stepped)
        option Sawtooth
        option Exponential
        option Logarithmic
        option Random Complex Diffusion
        option Dual Sine (Interference)
    comment === BASIC PARAMETERS ===
    positive cutoff_frequency 15000
    real modulation_center 1.0
    real modulation_depth 0.8
    positive modulation_frequency_divisor 150
    comment Pattern-scale meaning is mode-dependent (legacy-compatible)
    comment === ADVANCED ===
    real phase_offset 0.01
    positive second_divisor 300
    real randomness_amount 0.3
    comment === TIME MODIFICATIONS ===
    real tail_duration_s 1.0
    real fade_out_duration_s 0.5
    comment === MIX ===
    real wet_dry_percent 100
    boolean stereo_output 1
    comment For mono input, stereo_output widens only the wet path (12 ms)
    comment === VISUALIZATION ===
    boolean show_visualization 1
    comment === OUTPUT ===
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# ===== PRESET APPLICATION =====
presetName$ = "Custom"

if preset = 2
    modulation_type = 4
    modulation_center = 0.15
    modulation_depth = 2.8
    modulation_frequency_divisor = 8
    cutoff_frequency = 6000
    randomness_amount = 0.5
    phase_offset = 0.0
    presetName$ = "BrokenRadio"
elsif preset = 3
    modulation_type = 6
    modulation_center = 0.0
    modulation_depth = 5.0
    modulation_frequency_divisor = 30
    cutoff_frequency = 1200
    phase_offset = 0.0
    presetName$ = "DemonVoice"
elsif preset = 4
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = 3.0
    modulation_frequency_divisor = 6
    cutoff_frequency = 20000
    randomness_amount = 1.0
    phase_offset = 0.0
    presetName$ = "GlassShatter"
elsif preset = 5
    modulation_type = 4
    modulation_center = 0.0
    modulation_depth = 1.0
    modulation_frequency_divisor = 60
    cutoff_frequency = 18000
    phase_offset = 1.57
    presetName$ = "BlackHole"
elsif preset = 6
    modulation_type = 4
    modulation_center = 0.5
    modulation_depth = -2.5
    modulation_frequency_divisor = 18
    cutoff_frequency = 14000
    phase_offset = 0.0
    presetName$ = "BitRot"
elsif preset = 7
    modulation_type = 9
    modulation_center = 0.2
    modulation_depth = 2.5
    modulation_frequency_divisor = 9
    second_divisor = 10
    cutoff_frequency = 18000
    phase_offset = 0.0
    presetName$ = "InsectSwarm"
elsif preset = 8
    modulation_type = 2
    modulation_center = 0.3
    modulation_depth = 2.2
    modulation_frequency_divisor = 30
    cutoff_frequency = 20000
    phase_offset = 1.57
    presetName$ = "FrozenCathedral"
elsif preset = 9
    modulation_type = 5
    modulation_center = 0.5
    modulation_depth = -2.0
    modulation_frequency_divisor = 25
    cutoff_frequency = 8000
    phase_offset = 0.0
    presetName$ = "DyingMachine"
elsif preset = 10
    modulation_type = 9
    modulation_center = 0.0
    modulation_depth = 2.0
    modulation_frequency_divisor = 100
    second_divisor = 101
    cutoff_frequency = 16000
    phase_offset = 0.0
    presetName$ = "QuantumTunnel"
elsif preset = 11
    modulation_type = 8
    modulation_center = 0.3
    modulation_depth = 3.5
    modulation_frequency_divisor = 30
    cutoff_frequency = 5000
    randomness_amount = 0.9
    phase_offset = 0.0
    presetName$ = "VocalDestroyer"
elsif preset = 12
    modulation_type = 6
    modulation_center = 0.0
    modulation_depth = 8.0
    modulation_frequency_divisor = 20
    cutoff_frequency = 400
    phase_offset = 0.0
    presetName$ = "ThunderRumble"
elsif preset = 13
    modulation_type = 4
    modulation_center = 0.15
    modulation_depth = 3.0
    modulation_frequency_divisor = 5
    cutoff_frequency = 18000
    phase_offset = 0.0
    presetName$ = "CrystalFracture"
elsif preset = 14
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = -3.0
    modulation_frequency_divisor = 12
    cutoff_frequency = 12000
    randomness_amount = 0.95
    phase_offset = 0.0
    presetName$ = "ToxicWaste"
elsif preset = 15
    modulation_type = 1
    modulation_center = 0.05
    modulation_depth = 0.12
    modulation_frequency_divisor = 500
    cutoff_frequency = 8000
    phase_offset = 0.0
    presetName$ = "GhostSignal"
elsif preset = 16
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = 5.0
    modulation_frequency_divisor = 4
    cutoff_frequency = 20000
    randomness_amount = 1.0
    phase_offset = 0.0
    presetName$ = "NuclearMeltdown"
elsif preset = 17
    modulation_type = 4
    modulation_center = 0.0
    modulation_depth = 1.0
    modulation_frequency_divisor = 65
    cutoff_frequency = 16000
    phase_offset = 1.57
    presetName$ = "CelloHarmonicComb"
elsif preset = 18
    modulation_type = 8
    modulation_center = 0.2
    modulation_depth = 4.0
    modulation_frequency_divisor = 55
    cutoff_frequency = 16000
    randomness_amount = 1.0
    phase_offset = 0.0
    presetName$ = "CelloSpectralSmear"
elsif preset = 19
    modulation_type = 2
    modulation_center = 0.5
    modulation_depth = 3.5
    modulation_frequency_divisor = 60
    cutoff_frequency = 16000
    phase_offset = 0.78
    presetName$ = "CelloBodyResonanceWarp"
endif

# Set target sample rate to Full Quality ALWAYS
targetSR = 0
speedStr$ = "Full Quality"

# ===== PROCESSING SETUP =====
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSelectionID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalSelectionID
original_sr = Get sampling frequency
n_channels = Get number of channels
originalDuration = Get total duration

if n_channels > 2
    exitScript: "Spectral Painter v0.7 supports mono or stereo Sounds. Multichannel input is not silently truncated."
endif

# Validation. Zero is meaningful for tail/fade/randomness.
wet_dry_percent = max(0, min(100, wet_dry_percent))
randomness_amount = max(0, randomness_amount)
tail_duration_s = max(0, tail_duration_s)
fade_out_duration_s = max(0, fade_out_duration_s)
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Representative channel for measurement/visualization:
# choose the stronger RMS channel, never a phase-cancelling mono fold-down.
vizChannel = 1
if n_channels = 2
    selectObject: originalSelectionID
    Extract one channel: 1
    rmsProbe1ID = selected("Sound")
    rms1 = Get root-mean-square: 0, 0
    selectObject: originalSelectionID
    Extract one channel: 2
    rmsProbe2ID = selected("Sound")
    rms2 = Get root-mean-square: 0, 0
    if rms2 > rms1
        vizChannel = 2
    endif
    removeObject: rmsProbe1ID, rmsProbe2ID
endif

# Create padded working copy for the wet FFT path.
selectObject: originalSelectionID
Copy: "working_padded"
originalID = selected("Sound")

if tail_duration_s > 0
    Create Sound from formula: "sp_tail_silence", n_channels, 0, tail_duration_s, original_sr, "0"
    silenceID = selected("Sound")
    selectObject: originalID
    plusObject: silenceID
    Concatenate
    paddedID = selected("Sound")
    removeObject: originalID, silenceID
    originalID = paddedID
endif

selectObject: originalID
duration = Get total duration

effective_cutoff = min(cutoff_frequency, 0.5 * original_sr)
if effective_cutoff <= 0
    effective_cutoff = 0.5 * original_sr
endif

stopwatch

writeInfoLine:  "=============================================================="
appendInfoLine: "        SPECTRAL PAINTER v0.7"
appendInfoLine: "=============================================================="
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Speed:    ", speedStr$
appendInfoLine: "Type:     ", modulation_type
appendInfoLine: "Center:   ", modulation_center, "  |  Depth: ", modulation_depth
appendInfoLine: "Channels: ", n_channels, " | visualization channel: ", vizChannel
appendInfoLine: "Cutoff:   ", fixed$(effective_cutoff, 1), " Hz"
appendInfoLine: "Tail:     ", tail_duration_s, "s | wet fade: ", fade_out_duration_s, "s"
appendInfoLine: "Wet/Dry:  ", fixed$(wet_dry_percent, 0), "%"
if modulation_type = 1 or modulation_type = 2
    appendInfoLine: "Phase offset active (sine modes): ", phase_offset
else
    appendInfoLine: "Phase offset: not used for this modulation type"
endif
if modulation_type = 8
    appendInfoLine: "Random mode: independent real/imaginary per-bin perturbations; phase diffusion is intentional."
endif
appendInfoLine: ""

# ===================================================================
# Build modulation formula string
# ===================================================================
cenStr$ = string$(modulation_center)
depStr$ = string$(modulation_depth)
divStr$ = string$(modulation_frequency_divisor)
cutStr$ = string$(effective_cutoff)
phaseStr$ = string$(phase_offset)
rndStr$ = string$(randomness_amount)
secStr$ = string$(second_divisor)

if modulation_type = 1
    modName$ = "Sine (Linear)"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * sin(x / " + divStr$ + " + " + phaseStr$ + ")) else self fi"
elsif modulation_type = 2
    modName$ = "Sine (Log)"
    density_str$ = string$(modulation_frequency_divisor / 10)
    modFormula$ = "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * sin(ln(x) * " + density_str$ + " + " + phaseStr$ + ")) else self fi"
elsif modulation_type = 3
    modName$ = "Triangle"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (4 * abs((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)) - 1)) else self fi"
elsif modulation_type = 4
    modName$ = "Square"
    modFormula$ = "if x < " + cutStr$ + " then self * if sin(x / " + divStr$ + ") > 0 then " + cenStr$ + " + " + depStr$ + " else " + cenStr$ + " - " + depStr$ + " fi else self fi"
elsif modulation_type = 5
    modName$ = "Sawtooth"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * ((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)))) else self fi"
elsif modulation_type = 6
    modName$ = "Exponential"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * exp(-x / " + divStr$ + ")) else self fi"
elsif modulation_type = 7
    modName$ = "Logarithmic"
    modFormula$ = "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * ln(1 + x / " + divStr$ + ")) else self fi"
elsif modulation_type = 8
    modName$ = "Random Complex Diffusion"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + " + rndStr$ + " * randomGauss(0, 1))) else self fi"
else
    modName$ = "Dual Sine"
    modFormula$ = "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + 0.5 * sin(x / " + secStr$ + ")) / 1.5) else self fi"
endif

appendInfoLine: "Modulation: ", modName$

if targetSR > 0 and original_sr > targetSR
    workingSR = targetSR
else
    workingSR = original_sr
endif

# ===================================================================
# MAIN PROCESSING
# ===================================================================
appendInfoLine: "[1/4] Extracting and optionally downsampling channels..."

proc_channels = n_channels

origSpecID = 0
specID = 0

for ch from 1 to proc_channels
    appendInfoLine: "  Channel ", ch, " of ", proc_channels, ":"

    selectObject: originalID
    if n_channels > 1
        Extract one channel: ch
        chSoundID = selected("Sound")
    else
        Copy: "ch_work"
        chSoundID = selected("Sound")
    endif

    if targetSR > 0 and original_sr > targetSR
        appendInfoLine: "    Downsampling to ", targetSR, " Hz..."
        selectObject: chSoundID
        Resample: targetSR, 50
        resampledID = selected("Sound")
        removeObject: chSoundID
        chSoundID = resampledID
    endif

    appendInfoLine: "    [2/4] Spectrum..."
    selectObject: chSoundID
    To Spectrum: "yes"
    chOrigSpecID = selected("Spectrum")

    Copy: "modulated_ch" + string$(ch)
    chSpecID = selected("Spectrum")

    if ch = vizChannel
        origSpecID = chOrigSpecID
    else
        removeObject: chOrigSpecID
    endif

    appendInfoLine: "    [3/4] Modulation..."
    selectObject: chSpecID
    Formula: modFormula$

    if ch = vizChannel
        specID = chSpecID
    endif

    appendInfoLine: "    [4/4] Reconstruct..."
    selectObject: chSpecID
    To Sound
    chResultID = selected("Sound")

    if ch <> vizChannel
        removeObject: chSpecID
    endif

    selectObject: chResultID
    resultDur = Get total duration
    if resultDur > duration
        Extract part: 0, duration, "rectangular", 1, "no"
        trimmedID = selected("Sound")
        removeObject: chResultID
        chResultID = trimmedID
    endif

    if targetSR > 0 and original_sr > targetSR
        appendInfoLine: "    Upsampling back to ", original_sr, " Hz..."
        selectObject: chResultID
        Resample: original_sr, 50
        upsampledID = selected("Sound")
        removeObject: chResultID
        chResultID = upsampledID
    endif

    resultCh'ch' = chResultID
    removeObject: chSoundID
endfor

# ===================================================================
# WET FADE
# Fade belongs to the wet effect path, not to the dry reference.
# ===================================================================
if fade_out_duration_s > 0
    wetFadeDur = min(fade_out_duration_s, duration)
    wetFadeStart = duration - wetFadeDur
    appendInfoLine: "  Applying fade to wet path only..."
    for ch from 1 to proc_channels
        selectObject: resultCh'ch'
        Formula: "if x > " + string$(wetFadeStart) + " then self * (" + string$(duration) + " - x) / " + string$(wetFadeDur) + " else self fi"
    endfor
endif

# ===================================================================
# ASSEMBLE PURE WET OUTPUT
# Stereo source: preserve both independently processed channels.
# Mono source + stereo_output: widen only the wet path with 12 ms delay.
# ===================================================================
if proc_channels = 2
    appendInfoLine: "  Combining processed stereo channels..."
    selectObject: resultCh1
    plusObject: resultCh2
    Combine to stereo
    wetResultID = selected("Sound")
    removeObject: resultCh1, resultCh2
    out_channels = 2
else
    wetMonoID = resultCh1
    if stereo_output
        appendInfoLine: "  Widening mono wet path by 12 ms (dry remains centred)..."
        delay_samples = round(0.012 * original_sr)

        selectObject: wetMonoID
        Copy: "sp_wet_left"
        wetLeftID = selected("Sound")

        wetMonoIdStr$ = string$(wetMonoID)
        Create Sound from formula: "sp_wet_right", 1, 0, duration, original_sr,
            ... "if col > " + string$(delay_samples) + " then object[" + wetMonoIdStr$ + ", 1, col - " + string$(delay_samples) + "] else 0 fi"
        wetRightID = selected("Sound")

        selectObject: wetLeftID
        plusObject: wetRightID
        Combine to stereo
        wetResultID = selected("Sound")
        removeObject: wetMonoID, wetLeftID, wetRightID
        out_channels = 2
    else
        wetResultID = wetMonoID
        out_channels = 1
    endif
endif

# ===================================================================
# WET/DRY MIX
# The original user Sound is the dry reference. Samples beyond its duration
# evaluate to zero, so the effect tail remains wet-only.
# ===================================================================
resultID = wetResultID
if dry_level > 0
    appendInfoLine: "  Mixing wet/dry with untouched source as dry reference..."
    selectObject: resultID
    if n_channels = 2
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + string$(originalSelectionID) + ", row, col] * " + string$(dry_level)
    else
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + string$(originalSelectionID) + ", 1, col] * " + string$(dry_level)
    endif
endif

# ===================================================================
# SCALE & RENAME
# Dry-only output is not normalized: wet=0 behaves as an actual dry path.
# ===================================================================
selectObject: resultID
Rename: originalName$ + "_" + presetName$
if wet_level > 0
    Scale peak: scale_peak
endif

# ===================================================================
# VISUALIZATION
# v0.7: mechanism-first 2x2 layout. Every plotted curve is either the
# actual transfer realization used by the retained visualization channel,
# or a direct measurement of source / wet / final output.
# ===================================================================
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing measured process visualization..."

    # ---------------------------------------------------------------
    # Measurement objects
    # ---------------------------------------------------------------
    # Padded representative source channel.
    selectObject: originalID
    if n_channels > 1
        Extract one channel: vizChannel
        vizSrcID = selected("Sound")
    else
        Copy: "sp_viz_source"
        vizSrcID = selected("Sound")
    endif
    Rename: "sp_viz_source"

    # Representative final-output channel.
    selectObject: resultID
    if out_channels > 1
        vizOutChannel = min(vizChannel, out_channels)
        Extract one channel: vizOutChannel
        vizOutID = selected("Sound")
    else
        Copy: "sp_viz_output"
        vizOutID = selected("Sound")
    endif
    Rename: "sp_viz_output"

    selectObject: vizSrcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    srcRms = Get root-mean-square: 0, 0
    selectObject: vizOutID
    outPeak = Get absolute extremum: 0, 0, "None"
    outRms = Get root-mean-square: 0, 0
    waveRange = 1.08 * max(srcPeak, outPeak)
    if waveRange < 1e-6
        waveRange = 1
    endif

    if srcRms > 1e-12 and outRms > 1e-12
        rmsChangeDb = 20 * log10(outRms / srcRms)
    elsif outRms <= 1e-12
        rmsChangeDb = -300
    else
        rmsChangeDb = 60
    endif

    if tail_duration_s > 0
        selectObject: vizOutID
        tailRms = Get root-mean-square: originalDuration, duration
        if outRms > 1e-12 and tailRms > 1e-12
            tailRelDb = 20 * log10(tailRms / outRms)
        elsif tailRms <= 1e-12
            tailRelDb = -300
        else
            tailRelDb = 0
        endif
    else
        tailRms = 0
        tailRelDb = -300
    endif

    # Measured spectral metrics from the exact pre-mix Spectrum pair.
    selectObject: origSpecID
    srcCentroid = Get centre of gravity: 2
    To Ltas (1-to-1)
    origLtasID = selected("Ltas")

    selectObject: specID
    wetCentroid = Get centre of gravity: 2
    To Ltas (1-to-1)
    modLtasID = selected("Ltas")
    centroidDelta = wetCentroid - srcCentroid

    specFmin = 50
    nyquist = 0.5 * original_sr
    specFmax = min(0.48 * original_sr, max(1000, 1.25 * effective_cutoff))
    if specFmax > nyquist
        specFmax = nyquist
    endif
    if specFmax <= specFmin * 1.2
        specFmin = max(1, specFmax / 5)
    endif
    logFmin = log10(specFmin)
    logFmax = log10(specFmax)

    nSpecPoints = 88
    specFreq# = zero#(nSpecPoints)
    transferDb# = zero#(nSpecPoints)
    srcDb# = zero#(nSpecPoints)
    wetDb# = zero#(nSpecPoints)
    srcBandPower# = zero#(nSpecPoints)
    centrePhaseDeg# = zero#(nSpecPoints)

    dfSpec = object[origSpecID].dx
    nBinsSpec = object[origSpecID].nx
    maxTransferAbs = 0
    srcMaxBandPower = 0
    specMaxDb = -1e9

    # First pass: actual local power ratio and actual LTAS levels.
    for q from 1 to nSpecPoints
        frac = (q - 1) / (nSpecPoints - 1)
        freq = specFmin * (specFmax / specFmin)^frac
        specFreq#[q] = freq

        centreBin = round(freq / dfSpec) + 1
        halfBins = max(1, round(0.025 * freq / dfSpec))
        bLo = max(1, centreBin - halfBins)
        bHi = min(nBinsSpec, centreBin + halfBins)

        pSrc = 0
        pWet = 0
        for b from bLo to bHi
            sr = object[origSpecID, 1, b]
            si = object[origSpecID, 2, b]
            wr = object[specID, 1, b]
            wi = object[specID, 2, b]
            pSrc += sr^2 + si^2
            pWet += wr^2 + wi^2
        endfor
        srcBandPower#[q] = pSrc
        if pSrc > srcMaxBandPower
            srcMaxBandPower = pSrc
        endif

        if pSrc > 1e-300
            deltaDb = 10 * log10(max(1e-300, pWet) / pSrc)
        else
            deltaDb = 0
        endif
        # Keep the display readable; extreme spectral nulls are clipped.
        deltaDb = max(-60, min(60, deltaDb))
        transferDb#[q] = deltaDb
        if abs(deltaDb) > maxTransferAbs
            maxTransferAbs = abs(deltaDb)
        endif

        bandLoHz = max(specFmin, freq / 1.04)
        bandHiHz = min(specFmax, freq * 1.04)
        if bandHiHz <= bandLoHz
            bandHiHz = min(specFmax, bandLoHz + max(1, dfSpec))
        endif
        selectObject: origLtasID
        sdb = Get mean: bandLoHz, bandHiHz, "dB"
        selectObject: modLtasID
        wdb = Get mean: bandLoHz, bandHiHz, "dB"
        if sdb = undefined
            sdb = -300
        endif
        if wdb = undefined
            wdb = -300
        endif
        srcDb#[q] = sdb
        wetDb#[q] = wdb
        if sdb > specMaxDb
            specMaxDb = sdb
        endif
        if wdb > specMaxDb
            specMaxDb = wdb
        endif
    endfor

    # Phase-change QC at occupied centre bins.
    phaseSq = 0
    phaseCount = 0
    for q from 1 to nSpecPoints
        if srcBandPower#[q] > max(1e-300, srcMaxBandPower * 1e-6)
            centreBin = round(specFreq#[q] / dfSpec) + 1
            centreBin = max(1, min(nBinsSpec, centreBin))
            sr = object[origSpecID, 1, centreBin]
            si = object[origSpecID, 2, centreBin]
            wr = object[specID, 1, centreBin]
            wi = object[specID, 2, centreBin]
            if sr^2 + si^2 > 1e-300 and wr^2 + wi^2 > 1e-300
                ph0 = arctan2(si, sr)
                ph1 = arctan2(wi, wr)
                dph = ph1 - ph0
                while dph > pi
                    dph -= 2*pi
                endwhile
                while dph < -pi
                    dph += 2*pi
                endwhile
                phaseSq += dph^2
                phaseCount += 1
            endif
        endif
    endfor
    if phaseCount > 0
        phaseRmsDeg = sqrt(phaseSq / phaseCount) * 180 / pi
    else
        phaseRmsDeg = 0
    endif

    transferRange = 10 * ceiling((maxTransferAbs + 1) / 10)
    if transferRange < 10
        transferRange = 10
    endif
    if transferRange > 60
        transferRange = 60
    endif

    specHi = 10 * ceiling((specMaxDb + 5) / 10)
    specLo = specHi - 80
    if specHi <= specLo + 20
        specHi = specLo + 20
    endif

    procedure spVizStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all

    # ---------------- Header ----------------
    Select outer viewport: 0, 8, 0.00, 0.42
    Select inner viewport: 0, 8, 0.00, 0.42
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "Spectral Painter v0.7 - " + presetName$

    Select outer viewport: 0, 8, 0.43, 0.72
    Select inner viewport: 0, 8, 0.43, 0.72
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.34,0.34,0.40}"
    if modulation_type = 8
        Text: 0.5, "centre", 0.58, "half", "whole-sound FFT -> random complex-bin paint -> IFFT -> wet tail/fade -> dry mix | actual realization shown below"
    else
        Text: 0.5, "centre", 0.58, "half", "whole-sound FFT -> signed frequency mask -> IFFT -> wet tail/fade -> dry mix | negative mask = pi polarity flip"
    endif

    # ========================================================
    # A  PROCESS
    # ========================================================
    Select outer viewport: 0.18, 3.92, 0.84, 1.10
    Select inner viewport: 0.18, 3.92, 0.84, 1.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  PROCESS - what the algorithm actually changes"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    if modulation_type = 8
        Text: 0.01, "left", 0.18, "half", "random mode modifies Re and Im independently; it is intentionally more than a gain-only filter"
    else
        Text: 0.01, "left", 0.18, "half", "deterministic modes apply the same signed scalar to Re and Im at each frequency"
    endif

    Select outer viewport: 0.18, 3.92, 1.11, 3.12
    Select inner viewport: 0.38, 3.72, 1.26, 2.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975,0.975,0.978}", 0, 1, 0, 1

    # Four large process boxes.
    Paint rectangle: "{0.92,0.94,0.97}", 0.03, 0.22, 0.57, 0.82
    Paint rectangle: "{0.93,0.96,0.93}", 0.28, 0.49, 0.57, 0.82
    Paint rectangle: "{0.97,0.94,0.91}", 0.55, 0.76, 0.57, 0.82
    Paint rectangle: "{0.95,0.93,0.96}", 0.82, 0.98, 0.57, 0.82

    Colour: "Black"
    Line width: 1
    Draw rectangle: 0.03, 0.22, 0.57, 0.82
    Draw rectangle: 0.28, 0.49, 0.57, 0.82
    Draw rectangle: 0.55, 0.76, 0.57, 0.82
    Draw rectangle: 0.82, 0.98, 0.57, 0.82
    Draw line: 0.22, 0.695, 0.28, 0.695
    Draw line: 0.49, 0.695, 0.55, 0.695
    Draw line: 0.76, 0.695, 0.82, 0.695

    Font size: 7
    Text: 0.125, "centre", 0.70, "half", "source"
    Font size: 5
    Text: 0.125, "centre", 0.61, "half", "FFT X(f)"

    Font size: 7
    Text: 0.385, "centre", 0.70, "half", "paint"
    Font size: 5
    Text: 0.385, "centre", 0.61, "half", modName$

    Font size: 7
    Text: 0.655, "centre", 0.70, "half", "wet"
    Font size: 5
    Text: 0.655, "centre", 0.61, "half", "IFFT + tail"

    Font size: 7
    Text: 0.90, "centre", 0.70, "half", "output"
    Font size: 5
    Text: 0.90, "centre", 0.61, "half", fixed$(wet_dry_percent,0) + "\% wet"

    Font size: 7
    Colour: "{0.25,0.25,0.30}"
    if modulation_type = 8
        Text: 0.5, "centre", 0.37, "half", "Re X'(f) = gR(f) Re X(f)     Im X'(f) = gI(f) Im X(f)"
        Font size: 6
        Text: 0.5, "centre", 0.25, "half", "gR and gI contain independent Gaussian per-bin terms below the cutoff"
    else
        Text: 0.5, "centre", 0.37, "half", "X'(f) = g(f) X(f) below cutoff; X'(f) = X(f) above cutoff"
        Font size: 6
        Text: 0.5, "centre", 0.25, "half", "signed g(f): magnitude changes by abs(g); g < 0 adds a pi phase flip"
    endif
    Font size: 6
    Colour: "{0.42,0.42,0.46}"
    Text: 0.5, "centre", 0.10, "half", "cutoff " + fixed$(effective_cutoff,0) + " Hz | padded wet duration " + fixed$(duration,2) + " s"

    # ========================================================
    # B  ACTUAL TRANSFER
    # ========================================================
    Select outer viewport: 4.08, 7.82, 0.84, 1.10
    Select inner viewport: 4.08, 7.82, 0.84, 1.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  PAINT - measured spectral change, actual realization"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.01, "left", 0.18, "half", "representative channel " + string$(vizChannel) + " | RMS phase change " + fixed$(phaseRmsDeg,1) + " deg | display clipped at +/-60 dB"

    Select outer viewport: 4.08, 7.82, 1.11, 3.12
    Select inner viewport: 4.55, 7.68, 1.22, 2.94
    Axes: logFmin, logFmax, -transferRange, transferRange
    Paint rectangle: "{0.975,0.975,0.978}", logFmin, logFmax, -transferRange, transferRange

    Colour: "{0.72,0.72,0.75}"
    Line width: 1
    Draw line: logFmin, 0, logFmax, 0

    if effective_cutoff >= specFmin and effective_cutoff <= specFmax
        cutX = log10(effective_cutoff)
        Colour: "{0.62,0.62,0.66}"
        Draw line: cutX, -transferRange, cutX, transferRange
    endif

    Colour: "{0.25,0.48,0.78}"
    Line width: 1.8
    for q from 2 to nSpecPoints
        x0 = log10(specFreq#[q-1])
        x1 = log10(specFreq#[q])
        Draw line: x0, transferDb#[q-1], x1, transferDb#[q]
    endfor
    Line width: 1

    Select inner viewport: 4.55, 7.68, 1.22, 2.94
    Axes: logFmin, logFmax, -transferRange, transferRange
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, max(5, transferRange/3), "yes", "yes", "no"

    # Manual log-frequency ticks.
    for fm from 1 to 8
        if fm = 1
            fmark = 50
            flab$ = "50"
        elsif fm = 2
            fmark = 100
            flab$ = "100"
        elsif fm = 3
            fmark = 200
            flab$ = "200"
        elsif fm = 4
            fmark = 500
            flab$ = "500"
        elsif fm = 5
            fmark = 1000
            flab$ = "1k"
        elsif fm = 6
            fmark = 2000
            flab$ = "2k"
        elsif fm = 7
            fmark = 5000
            flab$ = "5k"
        else
            fmark = 10000
            flab$ = "10k"
        endif
        if fmark >= specFmin and fmark <= specFmax
            One mark bottom: log10(fmark), "no", "yes", "no", flab$
        endif
    endfor
    if specFmax >= 16000
        One mark bottom: log10(16000), "no", "yes", "no", "16k"
    endif
    Font size: 6
    Text left: "yes", "change (dB)"
    Text bottom: "yes", "frequency"

    # ========================================================
    # C  SOURCE vs PAINTED WET SPECTRUM
    # ========================================================
    Select outer viewport: 0.18, 3.92, 3.30, 3.56
    Select inner viewport: 0.18, 3.92, 3.30, 3.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  SPECTRUM - source vs painted wet on one shared scale"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.01, "left", 0.18, "half", "grey source | blue wet before dry mix / peak scaling | centroid shift " + fixed$(centroidDelta,0) + " Hz"

    Select outer viewport: 0.18, 3.92, 3.57, 5.48
    Select inner viewport: 0.62, 3.78, 3.68, 5.30
    Axes: logFmin, logFmax, specLo, specHi
    Paint rectangle: "{0.975,0.975,0.978}", logFmin, logFmax, specLo, specHi

    if effective_cutoff >= specFmin and effective_cutoff <= specFmax
        cutX = log10(effective_cutoff)
        Colour: "{0.74,0.74,0.77}"
        Draw line: cutX, specLo, cutX, specHi
    endif

    Colour: "{0.48,0.48,0.52}"
    Line width: 1.4
    for q from 2 to nSpecPoints
        y0 = max(specLo, min(specHi, srcDb#[q-1]))
        y1 = max(specLo, min(specHi, srcDb#[q]))
        Draw line: log10(specFreq#[q-1]), y0, log10(specFreq#[q]), y1
    endfor

    Colour: "{0.25,0.48,0.78}"
    Line width: 1.8
    for q from 2 to nSpecPoints
        y0 = max(specLo, min(specHi, wetDb#[q-1]))
        y1 = max(specLo, min(specHi, wetDb#[q]))
        Draw line: log10(specFreq#[q-1]), y0, log10(specFreq#[q]), y1
    endfor
    Line width: 1

    Select inner viewport: 0.62, 3.78, 3.68, 5.30
    Axes: logFmin, logFmax, specLo, specHi
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, 20, "yes", "yes", "no"
    for fm from 1 to 8
        if fm = 1
            fmark = 50
            flab$ = "50"
        elsif fm = 2
            fmark = 100
            flab$ = "100"
        elsif fm = 3
            fmark = 200
            flab$ = "200"
        elsif fm = 4
            fmark = 500
            flab$ = "500"
        elsif fm = 5
            fmark = 1000
            flab$ = "1k"
        elsif fm = 6
            fmark = 2000
            flab$ = "2k"
        elsif fm = 7
            fmark = 5000
            flab$ = "5k"
        else
            fmark = 10000
            flab$ = "10k"
        endif
        if fmark >= specFmin and fmark <= specFmax
            One mark bottom: log10(fmark), "no", "yes", "no", flab$
        endif
    endfor
    if specFmax >= 16000
        One mark bottom: log10(16000), "no", "yes", "no", "16k"
    endif
    Font size: 6
    Text left: "yes", "level (dB/Hz)"
    Text bottom: "yes", "frequency"

    # ========================================================
    # D  TIME RESULT
    # ========================================================
    Select outer viewport: 4.08, 7.82, 3.30, 3.56
    Select inner viewport: 4.08, 7.82, 3.30, 3.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "D  TIME - source and final output on the same amplitude scale"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    if tail_duration_s > 0
        Text: 0.01, "left", 0.18, "half", "top source | bottom final | source-end marker at " + fixed$(originalDuration,2) + " s | tail RMS " + fixed$(tailRelDb,1) + " dB vs output"
    else
        Text: 0.01, "left", 0.18, "half", "top source | bottom final | shared +/-" + fixed$(waveRange,3) + " amplitude range"
    endif

    # Source lane.
    Select outer viewport: 4.08, 7.82, 3.57, 4.48
    Select inner viewport: 4.55, 7.68, 3.66, 4.37
    selectObject: vizSrcID
    Colour: "{0.48,0.48,0.52}"
    Draw: 0, duration, -waveRange, waveRange, "no", "Curve"
    Select inner viewport: 4.55, 7.68, 3.66, 4.37
    Axes: 0, duration, -waveRange, waveRange
    if tail_duration_s > 0
        Colour: "{0.72,0.72,0.75}"
        Draw line: originalDuration, -waveRange, originalDuration, waveRange
    endif
    Colour: "Black"
    Draw inner box
    Font size: 5
    One mark left: 0, "no", "yes", "no", "0"
    Font size: 6
    Text left: "yes", "source"

    # Final-output lane.
    Select outer viewport: 4.08, 7.82, 4.55, 5.48
    Select inner viewport: 4.55, 7.68, 4.64, 5.30
    selectObject: vizOutID
    Colour: "{0.25,0.48,0.78}"
    Draw: 0, duration, -waveRange, waveRange, "no", "Curve"
    Select inner viewport: 4.55, 7.68, 4.64, 5.30
    Axes: 0, duration, -waveRange, waveRange
    if tail_duration_s > 0
        Colour: "{0.72,0.72,0.75}"
        Draw line: originalDuration, -waveRange, originalDuration, waveRange
    endif
    Colour: "Black"
    Draw inner box
    Font size: 5
    @spVizStep: duration, 5
    Marks bottom every: 1, spVizStep.step, "yes", "yes", "no"
    One mark left: 0, "no", "yes", "no", "0"
    Font size: 6
    Text left: "yes", "output"
    Text bottom: "yes", "time (s)"

    # ---------------- Summary ----------------
    Select outer viewport: 0, 8, 5.62, 6.04
    Select inner viewport: 0, 8, 5.62, 6.04
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.40}"
    summary$ = modName$ + " | cutoff " + fixed$(effective_cutoff,0) + " Hz | wet " + fixed$(wet_dry_percent,0) + "\% | tail " + fixed$(tail_duration_s,2) + " s | RMS change " + fixed$(rmsChangeDb,1) + " dB | phase RMS " + fixed$(phaseRmsDeg,1) + " deg"
    Text: 0.5, "centre", 0.58, "half", summary$

    Font size: 10
    Colour: "Black"

    removeObject: vizSrcID, vizOutID, origLtasID, modLtasID
endif

# ===================================================================
# CLEANUP
# ===================================================================
# We clean up originalID (which is the padded working copy), 
# leaving the user's actual sound untouched in the Objects list.
removeObject: origSpecID, specID, originalID

processingTime = stopwatch

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    Play
endif

selectObject: resultID
# ============================================================
# END OF SCRIPT
# ============================================================
