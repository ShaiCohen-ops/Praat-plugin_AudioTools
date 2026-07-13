# ============================================================
# Praat AudioTools - Basic_Mirror.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.2 (2026)
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
#   Spectral mirroring effect - high-frequency content is
#   reflected around a mirror point and added below the cutoff,
#   for creative harmonic/inharmonic textures.
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

form Spectral Mirror v0.3.2
    optionmenu Preset: 2
        option Mild (cutoff = Nyquist/4)
        option Moderate (cutoff = Nyquist/2)
        option Strong (cutoff = Nyquist/8)
        option Extreme (cutoff = Nyquist/16)
        option Custom
    optionmenu Character: 1
        option legacy texture (the original: phase-crush + chunk pulse)
        option clean mirror (precise spectral mirror)
    comment === Custom Cutoff ===
    positive Cutoff_divisor 2
    comment (Higher = lower cutoff = more mirroring)
    comment === Stereo Width ===
    real Stereo_spread 0.25
    real Stereo_mirror_offset 0.15
    comment === Mix ===
    real Dry_wet_mix 0.7
    positive Scale_peak 0.9
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

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
writeInfoLine: "=== Spectral Mirror v0.3.2 ==="
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

appendInfoLine: " done"
appendInfoLine: "L channel: cutoff=", cutoffL, " Hz, mirror=", nyquistL, " Hz"
appendInfoLine: "R channel: cutoff=", cutoffR, " Hz, mirror=", nyquistR, " Hz"
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
    
    # Mirror formula (v0.3): frozen-copy reads, row-aware, Hz
    # domain -- the reflected bin is (mirrorHz - x) converted
    # through the bin width. The old self[1, col] wrote the real
    # row into both rows (phase destruction), and treated Hz
    # values as bin indices.
    cutoffL$ = string$(cutoffL)
    nyquistL$ = string$(nyquistL)
    if character = 2
        selectObject: specL
        dxL = Get bin width
        frozenL = Copy: "frozenL"
        frozenL$ = string$(frozenL)
        dxL$ = fixed$(dxL, 10)
        selectObject: specL
        Formula: "if x < " + cutoffL$ + " then self + object[" + frozenL$
            ... + ", row, (" + nyquistL$ + " - x) / " + dxL$ + " + 1] else self endif"
        removeObject: frozenL
    else
        selectObject: specL
        Formula: "if col < " + cutoffL$ + " then self[1, col] + self[1, " + nyquistL$ + " - col] else self[1, col] endif"
    endif
    
    selectObject: specL
    procL = To Sound
    
    # Trim back to actual duration if padded. The mirrored band is
    # TIME-REVERSED content (see header note): in a padded chunk
    # part of the image lands in the pad, and the trim cuts it
    # mid-swing -- a click. 5 ms fade at the cut edge.
    selectObject: procL
    if actualDur < chunkDur
        trimL = Extract part: 0, actualDur, "rectangular", 1, "no"
        removeObject: procL
        procL = trimL
        if character = 2
            fadeMs = min(0.005, actualDur / 4)
            Fade out: 0, actualDur, -fadeMs, "yes"
        endif
    endif
    Rename: "procL"
    
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
        Formula: "if x < " + cutoffR$ + " then self + object[" + frozenR$
            ... + ", row, (" + nyquistR$ + " - x) / " + dxR$ + " + 1] else self endif"
        removeObject: frozenR
    else
        selectObject: specR
        Formula: "if col < " + cutoffR$ + " then self[1, col] + self[1, " + nyquistR$ + " - col] else self[1, col] endif"
    endif
    
    selectObject: specR
    procR = To Sound
    
    selectObject: procR
    if actualDur < chunkDur
        trimR = Extract part: 0, actualDur, "rectangular", 1, "no"
        removeObject: procR
        procR = trimR
        if character = 2
            fadeMs = min(0.005, actualDur / 4)
            Fade out: 0, actualDur, -fadeMs, "yes"
        endif
    endif
    Rename: "procR"
    
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
Scale peak: scale_peak
Rename: originalName$ + "_mirror_" + presetName$

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    # Create spectra for comparison
    selectObject: dryID
    drySpecID = To Spectrum: "yes"
    
    selectObject: stereoID
    resultMono = Convert to mono
    resSpecID = To Spectrum: "yes"
    removeObject: resultMono
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Mirror: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.5, 3.7, 0.75, 1.85
    
    selectObject: dryID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    # Processed waveform (mono mix for display)
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.5, 7.7, 0.75, 1.85
    
    selectObject: stereoID
    Colour: "{0.3, 0.6, 0.9}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Mirrored (stereo)"
    Text left: "yes", "Amp"
    
    # Spectrum comparison
    Select outer viewport: 0, 8, 2.2, 4.5
    Select inner viewport: 0.6, 7.6, 2.5, 4.3
    
    selectObject: drySpecID
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    Draw: 0, 8000, 0, 80, "no"
    
    selectObject: resSpecID
    Colour: "{0.3, 0.6, 0.9}"
    Line width: 2
    Draw: 0, 8000, 0, 80, "no"
    
    # Mark cutoff frequencies
    Axes: 0, 8000, 0, 80
    Colour: "{0.9, 0.4, 0.4}"
    Line width: 1
    Dotted line
    Draw line: baseCutoff, 0, baseCutoff, 80
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Spectrum (gray=original, blue=mirrored)"
    Text left: "yes", "Level (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Mark cutoff on plot
    Font size: 7
    Colour: "{0.9, 0.4, 0.4}"
    Text: baseCutoff, "centre", 75, "half", "cutoff"
    
    # Mirror diagram
    Select outer viewport: 0, 4, 4.7, 6.2
    Select inner viewport: 0.5, 3.7, 4.9, 6.0
    
    Axes: 0, nyquist, 0, 1
    
    # Draw original spectrum region
    Colour: "{0.8, 0.8, 0.8}"
    Paint rectangle: "{0.85, 0.85, 0.85}", 0, nyquist, 0, 0.5
    
    # Draw mirrored region
    Paint rectangle: "{0.7, 0.85, 1.0}", 0, baseCutoff, 0.5, 1
    
    # Draw mirror arrow
    Colour: "{0.9, 0.4, 0.4}"
    Line width: 2
    # Arrow from high freq to low freq (mirroring)
    Draw arrow: nyquist * 0.7, 0.25, baseCutoff * 0.5, 0.75
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Mirror operation"
    Text bottom: "yes", "Frequency"
    
    # Info panel
    Select outer viewport: 4, 8, 4.7, 6.2
    Select inner viewport: 4.4, 7.8, 4.9, 6.0
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.85, "half", "Preset: " + presetName$
    Text: 0.05, "left", 0.65, "half", "Cutoff: " + string$(baseCutoff) + " Hz (Nyquist/" + string$(cutoff_divisor) + ")"
    Text: 0.05, "left", 0.45, "half", "Stereo spread: " + fixed$(stereo_spread * 100, 0) + "%"
    Text: 0.05, "left", 0.25, "half", "Dry/Wet: " + fixed$((1 - dry_wet_mix) * 100, 0) + "/" + fixed$(dry_wet_mix * 100, 0) + "%"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    
    removeObject: drySpecID, resSpecID
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
