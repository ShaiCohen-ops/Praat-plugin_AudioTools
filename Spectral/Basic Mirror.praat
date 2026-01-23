# ============================================================
# Praat AudioTools - Basic_Mirror.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed formula syntax, added visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral mirroring effect - reflects frequencies around
#   a cutoff point for creative harmonic/inharmonic textures
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Spectral Mirror v0.2
    optionmenu Preset: 2
        option Mild (cutoff = Nyquist/4)
        option Moderate (cutoff = Nyquist/2)
        option Strong (cutoff = Nyquist/8)
        option Extreme (cutoff = Nyquist/16)
        option Custom
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
writeInfoLine: "=== Spectral Mirror v0.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Preset: ", presetName$
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
chunkSamples = 32768
chunkDur = chunkSamples / processing_sample_rate
overlapDur = 0.02
hopDur = chunkDur - overlapDur
numChunks = ceiling(total_dur / hopDur)

appendInfoLine: "Processing ", numChunks, " chunks..."

# Create output buffers
outputL = Create Sound from formula: "outputL", 1, 0, total_dur, processing_sample_rate, "0"
outputR = Create Sound from formula: "outputR", 1, 0, total_dur, processing_sample_rate, "0"

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
    
    # Mirror formula: add reflected frequencies below cutoff
    cutoffL$ = string$(cutoffL)
    nyquistL$ = string$(nyquistL)
    selectObject: specL
    Formula: "if col < " + cutoffL$ + " then self[1, col] + self[1, " + nyquistL$ + " - col] else self[1, col] endif"
    
    selectObject: specL
    procL = To Sound
    
    # Trim back to actual duration if padded
    selectObject: procL
    if actualDur < chunkDur
        trimL = Extract part: 0, actualDur, "rectangular", 1, "no"
        removeObject: procL
        procL = trimL
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
    selectObject: specR
    Formula: "if col < " + cutoffR$ + " then self[1, col] + self[1, " + nyquistR$ + " - col] else self[1, col] endif"
    
    selectObject: specR
    procR = To Sound
    
    selectObject: procR
    if actualDur < chunkDur
        trimR = Extract part: 0, actualDur, "rectangular", 1, "no"
        removeObject: procR
        procR = trimR
    endif
    Rename: "procR"
    
    selectObject: outputR
    Formula (part): chunkStart, chunkEnd, 1, 1, "self + Sound_procR(x - " + chunkStartStr$ + ")"
    
    removeObject: specR, procR, chunkID
endfor

# Normalize overlap-add gain
selectObject: outputL
Formula: "self * 0.5"
selectObject: outputR
Formula: "self * 0.5"

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

# Scale wet signals
selectObject: outputL
Scale peak: 0.95
selectObject: outputR
Scale peak: 0.95

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


