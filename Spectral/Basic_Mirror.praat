# ============================================================
# Praat AudioTools - Basic_Mirror.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
#
# Changelog v0.4.1 (2026) -- visualization and documentation only:
#   - VERIFIED BY MEASUREMENT, both characters. Clean engine, cutoff 8000 Hz,
#     sum 13600 Hz: 10000 -> 3600, 12000 -> 1600, 6000 -> 7600, all exactly
#     sum - f, at unity gain against the retained identity. Legacy: 6000 ->
#     ~7250, about 2.4% off, which is precisely the bin-index-as-Hz offset
#     documented in v0.3 and deliberately preserved. Both engines do what
#     their labels say.
#   - DESCRIPTION corrected. It said high-frequency content is reflected and
#     added below the cutoff. Measurement shows content already below the
#     cutoff is reflected too, and can land ABOVE its source. This is a
#     reflection of the whole band about the axis, output-limited to below
#     the cutoff, not a one-way downward fold.
#   - Every panel now carries axis numbers. Panel C exists to show where the
#     mirror image landed and previously had no frequency or level scale at
#     all, so the reader could not read off the one fact it was drawn for.
#     Frequency marks print in kHz rather than Praat's 10^4 notation.
#   - Panel C now names the measured strongest dry component and the measured
#     strongest wet-L component, so the reflection is stated by the figure.
#   - PANEL B REDRAWN. The law is f -> sum - f about the axis sum/2, so it is
#     now one shared frequency line with the receiving band shaded, the axis
#     marked and labelled per channel, and folds drawn from source to
#     destination with the landing point dotted. The old two-row diagram
#     needed the caption "arcs are bin mappings, not pitch trajectories" to
#     be read at all; a caption apologising for a picture means the picture
#     is fighting the law it depicts.
#   - Panel A left untouched apart from axis numbers: the Hann frames against
#     the overlap sum is the strongest thing in this figure. It does not
#     illustrate the v0.3 COLA fix, it demonstrates it, and switching
#     character shows the legacy window sum breathing down to zero -- which
#     is the argument for legacy being an instrument rather than a bug.
#
# Changelog v0.4 (2026):
#   - MUSICAL PRIORITY: legacy texture remains the default and its DSP path
#     is unchanged. The clean engine is corrected where the old behaviour
#     could suppress the mirror itself, especially on short files/tails.
#   - FIX (clean engine): partial FFT chunks no longer discard the reflected
#     component. The identity stays at the chunk start while the time-reversed
#     mirror image is realigned from the end of the zero-padded FFT buffer.
#     Full chunks retain the same complex-bin mirror law.
#   - VALIDATION: bounded mix/spread/output controls and safe custom cutoff.
#   - FORM: compact main controls; secondary mirror/output controls moved to
#     Edit details.
#   - VISUALIZATION: process-oriented display -- chunk/window geometry, actual
#     frequency-bin reflection for L/R, measured dry-vs-wet spectra, and final
#     stereo output. Legacy bin-space mapping is shown as such rather than
#     mislabeled as exact Hz.
#
# Changelog v0.3.2 (2026):
#   - The legacy texture is now the DEFAULT and first option:
#     after A/B listening, the composer judged the original
#     phase-crushed, chunk-breathing sound to be this tool's true
#     identity. The clean mirror engine (measured-correct per the
#     labels) remains as the alternate character. The legacy path
#     is bit-identical to v0.2 (verified: max sample diff = 0).
#
# Changelog v0.3.1 (2026):
#   - ADDED Character menu. v0.3's fixes changed the sound: the
#     old build's phase-mangled spectrum and near-non-overlapping
#     Hann chunks produced a crushed, breathing texture that is a
#     legitimate instrument in its own right. "legacy texture
#     (v0.2)" reproduces that path verbatim -- old formula, old
#     chunk geometry, flat 0.5 normalization, independent channel
#     scaling -- as a deliberate choice rather than an accident.
#     "clean mirror" is the corrected engine.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral mirroring effect - spectral content is reflected
#   about a mirror axis and the reflected image is added wherever
#   it lands below the cutoff, for creative harmonic/inharmonic
#   textures.
#
#   MEASURED BEHAVIOUR (clean engine, cutoff 8000 Hz, sum 13600 Hz
#   so the axis sits at 6800 Hz): the law is f -> sum - f, and the
#   identity is retained. 10000 Hz lands at 3600 Hz and 12000 Hz at
#   1600 Hz, so high content does fold down; but content ALREADY
#   below the cutoff is reflected too, and 6000 Hz lands at
#   7600 Hz - upward. This is a reflection of the whole band about
#   the axis, output-limited to below the cutoff, not a one-way
#   downward fold of the high band. Images arrive at unity gain
#   against the retained identity.
#
#   CHARACTER NOTE: the mirror adds COMPLEX bins in reversed
#   frequency order, and by X(-f) = conj(X(f)) such content is
#   TIME-REVERSED audio in the mirrored band (the same physics
#   measured in Non-Linear_Frequency_Folding v0.3.1). Transient
#   material grows reversed pre-images below the cutoff -- part
#   of this effect's identity.
#
#   Processing runs at a fixed 32 kHz so preset cutoffs are
#   consistent across sources; the WET path therefore carries
#   nothing above 16 kHz (the dry path stays full-rate).
#
# Changelog v0.3 (2026):
#   - FIX (audible, severe): chunk overlap-add used 1.024 s Hann
#     windows at 98% hop -- windows barely overlapped, so the
#     output amplitude rode each chunk's Hann shape, dipping to
#     near-silence every second (measured: 26 dB envelope swing
#     on a steady tone). Now 50% hop (Hann-COLA) with exact
#     analytic window-sum normalization (edges included); the
#     flat *0.5 "normalization" is gone.
#   - FIX (audible): the spectral formula wrote self[1, col] --
#     the REAL row -- into BOTH spectrum rows: phase destroyed on
#     every run, in both branches; and row 2 then read row 1
#     after it had been overwritten. Reads now come from a frozen
#     copy, row-aware.
#   - FIX: cutoff and mirror point were compared against col (bin
#     index) while the form, info lines, and viz all speak HERTZ.
#     The 32768-sample / 32 kHz chunks made bins ~= Hz (within
#     2.4%), masking the bug. Now x-domain with the reflection
#     index converted through the measured bin width.
#   - FIX: the wet channels were peak-normalized INDEPENDENTLY
#     before the mix, destroying the L/R balance the stereo
#     spread creates. Now scaled jointly.
#   - FIX: final selection was empty unless Play ran.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Spectral Mirror v0.4
    optionmenu Preset: 2
        option Mild (cutoff = Nyquist/4)
        option Moderate (cutoff = Nyquist/2)
        option Strong (cutoff = Nyquist/8)
        option Extreme (cutoff = Nyquist/16)
        option Custom
    optionmenu Character: 1
        option legacy texture (the original: phase-crush + chunk pulse)
        option clean mirror (precise spectral mirror)
    real Dry_wet_mix 0.7
    real Stereo_spread 0.25
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Advanced defaults / optional details. beginPause keeps the main form compact
# while remaining a real second-stage control dialog in interactive Praat.
cutoff_divisor = 2
stereo_mirror_offset = 0.15
output_peak = 0.9

if edit_details
    beginPause: "Spectral Mirror - Details"
        real: "Custom cutoff divisor (>1)", cutoff_divisor
        real: "Stereo reflection-sum offset (0..0.9)", stereo_mirror_offset
        real: "Output peak (0..1]", output_peak
    endPause: "Run", 1
endif

# ============================================================
# PRESETS
# ============================================================

if preset = 1
    cutoff_divisor = 4
    presetName$ = "Mild"
elsif preset = 2
    cutoff_divisor = 2
    presetName$ = "Moderate"
elsif preset = 3
    cutoff_divisor = 8
    presetName$ = "Strong"
elsif preset = 4
    cutoff_divisor = 16
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Musical controls are intentionally permissive inside the useful range,
# but undefined reflection geometry is rejected rather than silently producing
# out-of-range Spectrum indices.
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry/wet mix must be between 0 and 1."
endif
if stereo_spread < 0 or stereo_spread > 0.9
    exitScript: "Stereo spread must be between 0 and 0.9."
endif
if stereo_mirror_offset < 0 or stereo_mirror_offset > 0.9
    exitScript: "Stereo mirror offset must be between 0 and 0.9."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be > 0 and <= 1."
endif
if preset = 5 and cutoff_divisor <= 1
    exitScript: "Custom cutoff divisor must be greater than 1."
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
original_sr = Get sampling frequency
original_duration = Get total duration
num_channels = Get number of channels

# Processing sample rate (fixed for consistency)
processing_sample_rate = 32000
if processing_sample_rate > original_sr
    processing_sample_rate = original_sr
endif

clearinfo
writeInfoLine: "=== Spectral Mirror v0.4 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Preset: ", presetName$
if character = 1
    appendInfoLine: "Character: legacy texture (original sound)"
else
    appendInfoLine: "Character: clean mirror"
endif
appendInfoLine: ""

# ============================================================
# PREPARE SIGNAL
# ============================================================

appendInfo: "Preparing..."

# Convert to mono for processing
if num_channels > 1
    selectObject: originalID
    monoID = Convert to mono
else
    selectObject: originalID
    monoID = Copy: "mono"
endif

# Keep dry signal at original rate
selectObject: monoID
dryID = Copy: "dry_temp"

# Downsample for faster processing
selectObject: monoID
current_sr = Get sampling frequency
did_downsample = 0

if processing_sample_rate < current_sr
    downsampledID = Resample: processing_sample_rate, 50
    removeObject: monoID
    monoID = downsampledID
    did_downsample = 1
else
    processing_sample_rate = current_sr
endif

selectObject: monoID
total_dur = Get total duration

# Calculate frequency parameters
nyquist = processing_sample_rate / 2
baseCutoff = round(nyquist / cutoff_divisor)
baseNyquist = round(nyquist)

# Stereo spread - different cutoffs for L/R
cutoffL = round(baseCutoff * (1 - stereo_spread))
cutoffR = round(baseCutoff * (1 + stereo_spread))
nyquistL = round(baseNyquist * (1 - stereo_mirror_offset))
nyquistR = round(baseNyquist * (1 + stereo_mirror_offset * 0.5))

if cutoffL < 10
    cutoffL = 10
endif
if cutoffR < 10
    cutoffR = 10
endif
if nyquistR > baseNyquist
    nyquistR = baseNyquist
endif
if nyquistL > baseNyquist
    nyquistL = baseNyquist
endif
if nyquistL < 20 or nyquistR < 20
    exitScript: "Stereo mirror offset leaves too little reflection bandwidth."
endif

# Keep every reflected lookup inside the positive-frequency Spectrum.
# This only affects pathological custom settings; the shipped presets are unchanged.
cutoffClamped = 0
if cutoffL >= nyquistL - 10
    cutoffL = nyquistL - 10
    cutoffClamped = 1
endif
if cutoffR >= nyquistR - 10
    cutoffR = nyquistR - 10
    cutoffClamped = 1
endif

axisL = nyquistL / 2
axisR = nyquistR / 2

appendInfoLine: " done"
if character = 2
    appendInfoLine: "L channel: target < ", cutoffL, " Hz; reflection axis=", fixed$(axisL, 1), " Hz"
    appendInfoLine: "R channel: target < ", cutoffR, " Hz; reflection axis=", fixed$(axisR, 1), " Hz"
else
    appendInfoLine: "Legacy bin-space mapping retained (Hz labels are only approximate at 32 kHz)."
endif
if cutoffClamped
    appendInfoLine: "Custom cutoff was limited to keep reflected bins in range."
endif
appendInfoLine: ""

# ============================================================
# CHUNKED PROCESSING
# ============================================================

# Chunk parameters
# v0.3: 50% hop (Hann-COLA). The old hop of chunkDur - 20 ms left
# the windows barely overlapping: the output rode each chunk's
# Hann shape, dipping to near-silence every second.
chunkSamples = 32768
chunkDur = chunkSamples / processing_sample_rate
if character = 2
    hopDur = chunkDur / 2
else
    # legacy geometry: windows barely overlap -> the breathing pulse
    hopDur = chunkDur - 0.02
endif
numChunks = ceiling(total_dur / hopDur)

appendInfoLine: "Processing ", numChunks, " chunks..."

# Create output buffers + analytic window-sum envelope (exact
# normalization, edges included)
outputL = Create Sound from formula: "outputL", 1, 0, total_dur, processing_sample_rate, "0"
outputR = Create Sound from formula: "outputR", 1, 0, total_dur, processing_sample_rate, "0"
envsumID = Create Sound from formula: "envsum", 1, 0, total_dur, processing_sample_rate, "0"

# Process each chunk
for chunk from 1 to numChunks
    chunkStart = (chunk - 1) * hopDur
    chunkEnd = chunkStart + chunkDur
    if chunkEnd > total_dur
        chunkEnd = total_dur
    endif
    actualDur = chunkEnd - chunkStart
    
    # Extract chunk with window
    selectObject: monoID
    chunkID = Extract part: chunkStart, chunkEnd, "Hanning", 1, "no"
    
    # v0.3: accumulate this chunk's analytic Hann into the
    # window-sum envelope
    csStr$ = fixed$(chunkStart, 8)
    adStr$ = fixed$(actualDur, 8)
    selectObject: envsumID
    Formula (part): chunkStart, chunkEnd, 1, 1,
        ... "self + 0.5 * (1 - cos(2*pi*(x - " + csStr$ + ") / " + adStr$ + "))"
    
    # Pad if needed (for FFT)
    selectObject: chunkID
    actualSamples = Get number of samples
    if actualSamples < chunkSamples
        padDur = (chunkSamples - actualSamples) / processing_sample_rate
        silenceID = Create Sound from formula: "sil", 1, 0, padDur, processing_sample_rate, "0"
        selectObject: chunkID
        plusObject: silenceID
        paddedID = Concatenate
        removeObject: chunkID, silenceID
        chunkID = paddedID
    endif
    
    # === LEFT CHANNEL ===
    selectObject: chunkID
    specL = To Spectrum: "no"

    cutoffL$ = string$(cutoffL)
    nyquistL$ = string$(nyquistL)
    if character = 2
        # Clean engine: create the MIRROR-ONLY component from a frozen complex
        # spectrum. For a partial zero-padded frame, complex frequency reversal
        # places the image at the END of the FFT buffer. Realign that image to
        # the valid chunk interval, then add the untouched windowed identity.
        selectObject: specL
        dxL = Get bin width
        frozenL = Copy: "frozenL"
        frozenL$ = string$(frozenL)
        dxL$ = fixed$(dxL, 10)
        selectObject: specL
        Formula: "if x < " + cutoffL$ + " and (" + nyquistL$ + " - x) >= 0 then object[" + frozenL$
            ... + ", row, (" + nyquistL$ + " - x) / " + dxL$ + " + 1] else 0 fi"
        removeObject: frozenL

        selectObject: specL
        mirrorFullL = To Sound
        selectObject: mirrorFullL
        mirrorFullDurL = Get total duration
        mirrorStartL = max(0, mirrorFullDurL - actualDur)
        mirrorL = Extract part: mirrorStartL, mirrorFullDurL, "rectangular", 1, "no"
        removeObject: mirrorFullL
        Rename: "mirrorL"

        selectObject: chunkID
        identityL = Extract part: 0, actualDur, "rectangular", 1, "no"
        Rename: "procL"
        Formula: "self + Sound_mirrorL(x)"
        procL = selected("Sound")
        removeObject: mirrorL
    else
        # Legacy path is intentionally untouched: bin-index-as-Hz mapping,
        # real-row duplication, and the original partial-chunk trim all form
        # part of the chosen phase-crushed texture.
        selectObject: specL
        Formula: "if col < " + cutoffL$ + " then self[1, col] + self[1, " + nyquistL$ + " - col] else self[1, col] endif"
        procL = To Sound
        selectObject: procL
        if actualDur < chunkDur
            trimL = Extract part: 0, actualDur, "rectangular", 1, "no"
            removeObject: procL
            procL = trimL
        endif
        Rename: "procL"
    endif

    # Add to output using overlap-add
    chunkStartStr$ = fixed$(chunkStart, 8)
    selectObject: outputL
    Formula (part): chunkStart, chunkEnd, 1, 1, "self + Sound_procL(x - " + chunkStartStr$ + ")"

    removeObject: specL, procL

    # === RIGHT CHANNEL ===
    selectObject: chunkID
    specR = To Spectrum: "no"

    cutoffR$ = string$(cutoffR)
    nyquistR$ = string$(nyquistR)
    if character = 2
        selectObject: specR
        dxR = Get bin width
        frozenR = Copy: "frozenR"
        frozenR$ = string$(frozenR)
        dxR$ = fixed$(dxR, 10)
        selectObject: specR
        Formula: "if x < " + cutoffR$ + " and (" + nyquistR$ + " - x) >= 0 then object[" + frozenR$
            ... + ", row, (" + nyquistR$ + " - x) / " + dxR$ + " + 1] else 0 fi"
        removeObject: frozenR

        selectObject: specR
        mirrorFullR = To Sound
        selectObject: mirrorFullR
        mirrorFullDurR = Get total duration
        mirrorStartR = max(0, mirrorFullDurR - actualDur)
        mirrorR = Extract part: mirrorStartR, mirrorFullDurR, "rectangular", 1, "no"
        removeObject: mirrorFullR
        Rename: "mirrorR"

        selectObject: chunkID
        identityR = Extract part: 0, actualDur, "rectangular", 1, "no"
        Rename: "procR"
        Formula: "self + Sound_mirrorR(x)"
        procR = selected("Sound")
        removeObject: mirrorR
    else
        selectObject: specR
        Formula: "if col < " + cutoffR$ + " then self[1, col] + self[1, " + nyquistR$ + " - col] else self[1, col] endif"
        procR = To Sound
        selectObject: procR
        if actualDur < chunkDur
            trimR = Extract part: 0, actualDur, "rectangular", 1, "no"
            removeObject: procR
            procR = trimR
        endif
        Rename: "procR"
    endif

    selectObject: outputR
    Formula (part): chunkStart, chunkEnd, 1, 1, "self + Sound_procR(x - " + chunkStartStr$ + ")"

    removeObject: specR, procR, chunkID
endfor

# v0.3: exact OLA normalization by the window-sum envelope.
# The correction is CAPPED (divide by max(env, 0.3)): the
# identity component shares the envelope's shape and cancels
# exactly, but the time-reversed image component does not, and an
# uncapped division amplified its remnants explosively where the
# envelope approaches zero (file edges, partial-chunk tails).
# The cap leaves a mild natural fade at the extreme file edges.
envStr$ = string$(envsumID)
if character = 2
    selectObject: outputL
    Formula: "self / max(object[" + envStr$ + ", col], 0.3)"
    selectObject: outputR
    Formula: "self / max(object[" + envStr$ + ", col], 0.3)"
else
    # legacy flat scale (part of the old sound's level behavior)
    selectObject: outputL
    Formula: "self * 0.5"
    selectObject: outputR
    Formula: "self * 0.5"
endif
removeObject: envsumID

appendInfoLine: "Processing complete"

# ============================================================
# RESAMPLE AND MIX
# ============================================================

appendInfo: "Mixing..."

# Resample back to original rate if needed
if did_downsample and original_sr > processing_sample_rate
    selectObject: outputL
    resampledL = Resample: original_sr, 50
    removeObject: outputL
    outputL = resampledL
    
    selectObject: outputR
    resampledR = Resample: original_sr, 50
    removeObject: outputR
    outputR = resampledR
endif

# Scale wet signals (v0.3: JOINTLY -- independent per-channel
# peaks destroyed the L/R balance the stereo spread creates)
if character = 2
    selectObject: outputL
    peakL = Get absolute extremum: 0, 0, "None"
    selectObject: outputR
    peakR = Get absolute extremum: 0, 0, "None"
    peakMax = max(peakL, peakR)
    if peakMax > 1e-9
        jointScale = 0.95 / peakMax
        selectObject: outputL
        Formula: "self * jointScale"
        selectObject: outputR
        Formula: "self * jointScale"
    endif
else
    # legacy: independent per-channel peaks (part of the old balance)
    selectObject: outputL
    Scale peak: 0.95
    selectObject: outputR
    Scale peak: 0.95
endif

# Preserve the pure wet channels only when they are needed for the
# process visualization. These copies never enter the audio path.
if draw_visualization
    selectObject: outputL
    wetVizL = Copy: "wet_viz_L"
    selectObject: outputR
    wetVizR = Copy: "wet_viz_R"
endif

# Mix dry/wet
wetMix$ = fixed$(dry_wet_mix, 4)
dryMix$ = fixed$(1 - dry_wet_mix, 4)

selectObject: outputL
Rename: "wetL"
Formula: "Sound_dry_temp(x) * " + dryMix$ + " + self * " + wetMix$

selectObject: outputR
Rename: "wetR"
Formula: "Sound_dry_temp(x) * " + dryMix$ + " + self * " + wetMix$

# Combine to stereo
selectObject: outputL
plusObject: outputR
stereoID = Combine to stereo

selectObject: stereoID
Scale peak: output_peak
Rename: originalName$ + "_mirror_" + presetName$

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing process visualization..."

    # Measured spectra: original mono vs PURE wet L/R before dry mixing.
    selectObject: dryID
    drySpecID = To Spectrum: "yes"
    selectObject: wetVizL
    wetSpecL = To Spectrum: "yes"
    selectObject: wetVizR
    wetSpecR = To Spectrum: "yes"

    # Final measured channels after the single stereo output scaling.
    selectObject: stereoID
    finalL = Extract one channel: 1
    Rename: "final_viz_L"
    selectObject: stereoID
    finalR = Extract one channel: 2
    Rename: "final_viz_R"

    selectObject: finalL
    peakFinalL = Get absolute extremum: 0, 0, "None"
    rmsFinalL = Get root-mean-square: 0, 0
    selectObject: finalR
    peakFinalR = Get absolute extremum: 0, 0, "None"
    rmsFinalR = Get root-mean-square: 0, 0
    vizPeak = max(peakFinalL, peakFinalR)
    if vizPeak < 1e-6
        vizPeak = 1
    else
        vizPeak = 1.05 * vizPeak
    endif

    # Effective mapping. The clean engine is in Hz. The legacy engine treats
    # its numeric "Hz" controls as BIN INDICES, so show the true effective
    # frequency geometry instead of repeating the historical label error.
    if character = 2
        mapCutL = cutoffL
        mapCutR = cutoffR
        mapSumL = nyquistL
        mapSumR = nyquistR
        mapLabel$ = "complex Hz-bin reflection"
    else
        legacyDx = processing_sample_rate / chunkSamples
        mapCutL = min(nyquist, max(0, (cutoffL - 1) * legacyDx))
        mapCutR = min(nyquist, max(0, (cutoffR - 1) * legacyDx))
        mapSumL = max(0, (nyquistL - 2) * legacyDx)
        mapSumR = max(0, (nyquistR - 2) * legacyDx)
        mapLabel$ = "legacy bin-space reflection"
    endif
    mapSrcLoL = max(0, mapSumL - mapCutL)
    mapSrcHiL = min(nyquist, mapSumL)
    mapSrcLoR = max(0, mapSumR - mapCutR)
    mapSrcHiR = min(nyquist, mapSumR)

    # Round mark steps. Marks left/bottom: N would place marks at the axis
    # extremes and print values like 15873.4.
    procedure vizStep: .range, .target
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
    Select outer viewport: 0, 8, 0, 0.42
    Select inner viewport: 0, 8, 0, 0.42
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.60, "half", "Spectral Mirror: " + originalName$ + " [" + presetName$ + "]"

    Select outer viewport: 0, 8, 0.44, 0.76
    Select inner viewport: 0, 8, 0.44, 0.76
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.42}"
    if character = 2
        process$ = "mono -> Hann frames / 50% OLA -> complex-bin reflection -> L/R mirror geometry -> dry/wet -> output"
    else
        process$ = "mono -> legacy near-disjoint Hann chunks -> phase-crushed bin reflection -> independent wet scaling -> dry/wet -> output"
    endif
    Text: 0.5, "centre", 0.5, "half", process$

    # ---------------- A title ----------------
    Select outer viewport: 0, 8, 0.82, 1.02
    Select inner viewport: 0, 8, 0.82, 1.02
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  Chunk geometry: analysis window and overlap sum"

    # ---------------- A data ----------------
    Select outer viewport: 0, 8, 1.04, 2.18
    Select inner viewport: 0.55, 7.75, 1.08, 2.08
    aXmax = 2 * chunkDur + hopDur
    Axes: 0, aXmax, 0, 1.25
    Colour: "{0.97, 0.97, 0.975}"
    Paint rectangle: "{0.97, 0.97, 0.975}", 0, aXmax, 0, 1.25

    # Three exact Hann windows from the selected character geometry.
    nDraw = 140
    for kk from 0 to 2
        ws = kk * hopDur
        Colour: "{0.45, 0.55, 0.72}"
        Line width: 1
        for q from 1 to nDraw
            t0 = ws + chunkDur * (q - 1) / nDraw
            t1 = ws + chunkDur * q / nDraw
            w0 = 0.5 * (1 - cos(2*pi*(q - 1)/nDraw))
            w1 = 0.5 * (1 - cos(2*pi*q/nDraw))
            Draw line: t0, w0, t1, w1
        endfor
    endfor

    # Window-sum curve -- the mechanism behind clean COLA vs legacy breathing.
    Colour: "{0.75, 0.25, 0.22}"
    Line width: 2
    for q from 1 to 260
        t0 = aXmax * (q - 1) / 260
        t1 = aXmax * q / 260
        sum0 = 0
        sum1 = 0
        for kk from 0 to 3
            ws = kk * hopDur
            if t0 >= ws and t0 <= ws + chunkDur
                u0 = (t0 - ws) / chunkDur
                sum0 = sum0 + 0.5 * (1 - cos(2*pi*u0))
            endif
            if t1 >= ws and t1 <= ws + chunkDur
                u1 = (t1 - ws) / chunkDur
                sum1 = sum1 + 0.5 * (1 - cos(2*pi*u1))
            endif
        endfor
        Draw line: t0, sum0, t1, sum1
    endfor
    Line width: 1
    Select inner viewport: 0.55, 7.75, 1.08, 2.08
    Axes: 0, aXmax, 0, 1.25
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02*aXmax, "left", 1.15, "half", "blue = Hann frames | red = overlap sum"

    Select inner viewport: 0.55, 7.75, 1.08, 2.08
    Axes: 0, aXmax, 0, 1.25
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1, 0.5, "yes", "yes", "no"
    @vizStep: aXmax, 6
    Marks bottom every: 1, vizStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "window / sum"

    Select outer viewport: 0, 8, 2.18, 2.34
    Select inner viewport: 0, 8, 2.18, 2.34
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    if character = 2
        chunkNote$ = "clean COLA normalization"
    else
        chunkNote$ = "legacy pulse is intentional character"
    endif
    Text: 0.5, "centre", 0.5, "half", "time in seconds  |  chunk=" + fixed$(chunkDur, 3) + " s  |  hop=" + fixed$(hopDur, 3) + " s  |  " + chunkNote$

    # ---------------- B title ----------------
    Select outer viewport: 0, 8, 2.40, 2.60
    Select inner viewport: 0, 8, 2.40, 2.60
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  Frequency reflection map: source band -> destination band"

    # ---------------- B data ----------------
    # ---------------- B: the reflection law on ONE frequency line ----------
    # The law is f -> S - f about the axis S/2, so it is drawn as a single
    # shared frequency axis with the axis and cutoff marked and a few labelled
    # folds. The previous two-row source/destination diagram needed the
    # caption "arcs are bin mappings, not pitch trajectories" to be read at
    # all, which is a sign the picture was fighting the law.
    Select outer viewport: 0, 8, 2.62, 3.78
    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.978}", 0, nyquist, 0, 1

    # Band that RECEIVES content, per channel.
    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    Paint rectangle: "{0.86, 0.91, 0.98}", 0, mapCutL, 0.10, 0.26
    Paint rectangle: "{0.96, 0.88, 0.84}", 0, mapCutR, 0.74, 0.90

    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    Font size: 5
    Colour: "{0.32, 0.52, 0.82}"
    Text: 0.006*nyquist, "left", 0.18, "half", "L receives < " + fixed$(mapCutL, 0) + " Hz"
    Colour: "{0.78, 0.38, 0.28}"
    Text: 0.006*nyquist, "left", 0.82, "half", "R receives < " + fixed$(mapCutR, 0) + " Hz"

    # Axis of reflection, per channel.
    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    axPosL = mapSumL / 2
    axPosR = mapSumR / 2
    Line width: 1
    Dashed line
    Colour: "{0.32, 0.52, 0.82}"
    if axPosL <= nyquist
        Draw line: axPosL, 0.10, axPosL, 0.50
    endif
    Colour: "{0.78, 0.38, 0.28}"
    if axPosR <= nyquist
        Draw line: axPosR, 0.50, axPosR, 0.90
    endif
    Solid line

    # Folds: a source frequency and where it lands, drawn as an arc that
    # actually goes from source to destination on the same axis.
    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    for m from 1 to 4
        fracB = m / 5
        srcL = mapSrcLoL + fracB * (mapSrcHiL - mapSrcLoL)
        dstL = mapSumL - srcL
        srcR = mapSrcLoR + fracB * (mapSrcHiR - mapSrcLoR)
        dstR = mapSumR - srcR

        if dstL >= 0 and dstL <= mapCutL and srcL <= nyquist
            Colour: "{0.32, 0.52, 0.82}"
            Line width: 1
            for q from 1 to 24
                u0 = (q-1)/24
                u1 = q/24
                x0 = srcL + (dstL - srcL) * u0
                x1 = srcL + (dstL - srcL) * u1
                y0 = 0.26 + 0.20 * sin(pi * u0)
                y1 = 0.26 + 0.20 * sin(pi * u1)
                Draw line: x0, y0, x1, y1
            endfor
            Paint circle (mm): "{0.32, 0.52, 0.82}", dstL, 0.26, 0.5
        endif

        if dstR >= 0 and dstR <= mapCutR and srcR <= nyquist
            Colour: "{0.78, 0.38, 0.28}"
            Line width: 1
            for q from 1 to 24
                u0 = (q-1)/24
                u1 = q/24
                x0 = srcR + (dstR - srcR) * u0
                x1 = srcR + (dstR - srcR) * u1
                y0 = 0.74 - 0.20 * sin(pi * u0)
                y1 = 0.74 - 0.20 * sin(pi * u1)
                Draw line: x0, y0, x1, y1
            endfor
            Paint circle (mm): "{0.78, 0.38, 0.28}", dstR, 0.74, 0.5
        endif
    endfor

    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    Font size: 5
    Colour: "{0.32, 0.52, 0.82}"
    if axPosL <= nyquist
        Text: axPosL, "centre", 0.56, "half", "axis " + fixed$(axPosL, 0) + " Hz"
    endif
    Colour: "{0.78, 0.38, 0.28}"
    if axPosR <= nyquist
        Text: axPosR, "centre", 0.44, "half", "axis " + fixed$(axPosR, 0) + " Hz"
    endif

    Select inner viewport: 0.85, 7.60, 2.70, 3.60
    Axes: 0, nyquist, 0, 1
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @vizStep: nyquist, 8
    stepB = vizStep.step
    nB = floor(nyquist / stepB)
    for q from 0 to nB
        fB = q * stepB
        if fB >= 1000
            labB$ = fixed$(fB / 1000, 1) + "k"
        else
            labB$ = fixed$(fB, 0)
        endif
        One mark bottom: fB, "no", "yes", "no", labB$
    endfor
    Font size: 6
    Text bottom: "yes", "frequency (Hz)"

    Select outer viewport: 0, 8, 3.78, 3.96
    Select inner viewport: 0, 8, 3.78, 3.96
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    if character = 2
        Text: 0.5, "centre", 0.5, "half", "reflection law: f -> sum - f, mirrored about sum/2 | the identity is kept, the image is added | " + mapLabel$
    else
        Text: 0.5, "centre", 0.5, "half", "legacy uses numeric Hz controls as FFT-bin indices; the plot shows their TRUE effective frequency mapping"
    endif

    # ---------------- C title ----------------
    Select outer viewport: 0, 8, 4.02, 4.22
    Select inner viewport: 0, 8, 4.02, 4.22
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  Measured spectrum: dry source vs pure mirrored wet channels"

    # ---------------- C data ----------------
    Select outer viewport: 0, 8, 4.24, 5.38
    Select inner viewport: 0.65, 7.75, 4.28, 5.28
    vizFreqMax = min(original_sr/2, 16000)
    selectObject: drySpecID
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, vizFreqMax, 0, 80, "no"
    selectObject: wetSpecL
    Colour: "{0.30, 0.52, 0.82}"
    Line width: 1
    Draw: 0, vizFreqMax, 0, 80, "no"
    selectObject: wetSpecR
    Colour: "{0.78, 0.38, 0.28}"
    Line width: 1
    Draw: 0, vizFreqMax, 0, 80, "no"
    Line width: 1

    # Identify what the panel is showing. The strongest dry component and the
    # strongest wet-L component are measured and named, so the reflection can
    # be read off the picture instead of inferred from it.
    selectObject: drySpecID
    dryPeakDb = -1000
    dryPeakHz = 0
    selectObject: wetSpecL
    wetPeakDb = -1000
    wetPeakHz = 0
    nProbe = 400
    for q from 1 to nProbe
        fLoP = vizFreqMax * (q - 1) / nProbe
        fHiP = vizFreqMax * q / nProbe
        selectObject: drySpecID
        dP = Get band density: fLoP, fHiP
        if dP <> undefined and dP > 0
            dDb = 10 * log10(dP)
            if dDb > dryPeakDb
                dryPeakDb = dDb
                dryPeakHz = (fLoP + fHiP) / 2
            endif
        endif
        selectObject: wetSpecL
        wP = Get band density: fLoP, fHiP
        if wP <> undefined and wP > 0
            wDb = 10 * log10(wP)
            if wDb > wetPeakDb
                wetPeakDb = wDb
                wetPeakHz = (fLoP + fHiP) / 2
            endif
        endif
    endfor

    Select inner viewport: 0.65, 7.75, 4.28, 5.28
    Axes: 0, vizFreqMax, 0, 80
    Font size: 5
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.02*vizFreqMax, "left", 75, "half", "gray dry | blue wet L | red wet R"
    Colour: "{0.30, 0.52, 0.82}"
    Text: 0.98*vizFreqMax, "right", 75, "half",
        ... "strongest dry " + fixed$(dryPeakHz, 0) + " Hz  ->  strongest wet L "
        ... + fixed$(wetPeakHz, 0) + " Hz"

    Select inner viewport: 0.65, 7.75, 4.28, 5.28
    Axes: 0, vizFreqMax, 0, 80
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1, 20, "yes", "yes", "no"
    @vizStep: vizFreqMax, 8
    stepC = vizStep.step
    nC = floor(vizFreqMax / stepC)
    for q from 0 to nC
        fC = q * stepC
        if fC >= 1000
            labC$ = fixed$(fC / 1000, 1) + "k"
        else
            labC$ = fixed$(fC, 0)
        endif
        One mark bottom: fC, "no", "yes", "no", labC$
    endfor
    Font size: 6
    Text left: "yes", "dB"

    Select outer viewport: 0, 8, 5.38, 5.54
    Select inner viewport: 0, 8, 5.38, 5.54
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "frequency in Hz; same frequency and level axes; wet spectra are measured BEFORE dry/wet mixing"

    # ---------------- D title ----------------
    Select outer viewport: 0, 8, 5.60, 5.80
    Select inner viewport: 0, 8, 5.60, 5.80
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "D  Measured final output (L/R, same amplitude scale)"

    # L waveform
    Select outer viewport: 0, 8, 5.82, 6.34
    Select inner viewport: 0.65, 7.75, 5.84, 6.30
    selectObject: finalL
    Colour: "{0.30, 0.52, 0.82}"
    Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
    Select inner viewport: 0.65, 7.75, 5.84, 6.30
    Axes: 0, original_duration, -vizPeak, vizPeak
    Font size: 5
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.995*original_duration, "right", 0.74*vizPeak, "half",
        ... "peak " + fixed$(peakFinalL, 3)

    Select inner viewport: 0.65, 7.75, 5.84, 6.30
    Axes: 0, original_duration, -vizPeak, vizPeak
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @vizStep: vizPeak, 2
    Marks left every: 1, vizStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "L"

    # R waveform
    Select outer viewport: 0, 8, 6.34, 6.86
    Select inner viewport: 0.65, 7.75, 6.36, 6.82
    selectObject: finalR
    Colour: "{0.78, 0.38, 0.28}"
    Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
    Select inner viewport: 0.65, 7.75, 6.36, 6.82
    Axes: 0, original_duration, -vizPeak, vizPeak
    Font size: 5
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.995*original_duration, "right", 0.74*vizPeak, "half",
        ... "peak " + fixed$(peakFinalR, 3)

    Select inner viewport: 0.65, 7.75, 6.36, 6.82
    Axes: 0, original_duration, -vizPeak, vizPeak
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @vizStep: vizPeak, 2
    Marks left every: 1, vizStep.step, "yes", "yes", "no"
    @vizStep: original_duration, 8
    Marks bottom every: 1, vizStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "R"
    Text bottom: "yes", "time (s)"

    # ---------------- QC strip ----------------
    Select outer viewport: 0, 8, 6.92, 7.52
    Select inner viewport: 0.15, 7.85, 6.94, 7.48
    Axes: 0, 3, 0, 2
    Colour: "{0.965, 0.965, 0.97}"
    Paint rectangle: "{0.965, 0.965, 0.97}", 0, 3, 0, 2
    Colour: "{0.82, 0.82, 0.84}"
    Draw line: 1, 0, 1, 2
    Draw line: 2, 0, 2, 2
    Draw line: 0, 1, 3, 1
    Colour: "Black"
    Draw rectangle: 0, 3, 0, 2
    Font size: 6
    if character = 2
        characterShort$ = "clean"
    else
        characterShort$ = "legacy"
    endif
    Text: 0.05, "left", 1.55, "half", "Character: " + characterShort$
    Text: 1.05, "left", 1.55, "half", "proc SR: " + fixed$(processing_sample_rate,0) + " Hz"
    Text: 2.05, "left", 1.55, "half", "chunks: " + string$(numChunks) + " | hop " + fixed$(hopDur,3) + " s"
    Text: 0.05, "left", 0.55, "half", "dry/wet: " + fixed$(dry_wet_mix,2) + " | spread " + fixed$(stereo_spread,2)
    Text: 1.05, "left", 0.55, "half", "L axis: " + fixed$(mapSumL/2,0) + " Hz | R: " + fixed$(mapSumR/2,0) + " Hz"
    Text: 2.05, "left", 0.55, "half", "peak L/R: " + fixed$(peakFinalL,3) + "/" + fixed$(peakFinalR,3) + " | RMS " + fixed$(rmsFinalL,3) + "/" + fixed$(rmsFinalR,3)

    removeObject: drySpecID, wetSpecL, wetSpecR, finalL, finalR, wetVizL, wetVizR
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoID, dryID, outputL, outputR

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_mirror_", presetName$

if play_result
    selectObject: stereoID
    Play
endif

selectObject: stereoID
