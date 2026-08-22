# ============================================================
# Praat AudioTools - Entropy_Modulated_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# v0.4.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Entropy-Modulated Dynamic Reverb - audio-reactive reverb
#   that analyzes spectral entropy (complexity) and uses it
#   to dynamically crossfade between "dark" (long, warm) and
#   "bright" (short, crisp) reverb characteristics. Low entropy
#   (tonal sounds) gets warm reverb; high entropy (noise,
#   consonants) gets bright reverb. Also modulates wet/dry.
#
# ============================================================

# Changelog v0.3:
#   - Public form/defaults, output naming, and final selection are unchanged.
#   - Added a private zero-based work copy for non-zero source xmin.
#   - Fixed stereo/multichannel control routing: mono entropy/wet controls
#     are read explicitly from row 1, while audio is read by row/column.
#   - Cross-object Formula reads use object IDs, avoiding same-name collisions
#     with temporary objects that may already exist in caller scripts.
#   - Custom smoothing alpha and dynamic wet bounds are sanitized internally.
#   - Entropy normalization guards the one-bin edge case.
#   - Mix duration now uses the longer of dark and bright convolutions.
#   - Dry and entropy controls are explicitly zero-padded to that duration.
#   - Safe Scale peak guards digital silence while preserving the existing
#     non-silent normalization behaviour.
#   - Caller-visible final selection remains the original Sound.
#
form Entropy-Modulated Reverb v0.4.1 COMPATIBLE
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Reactive
        option Medium Reactive
        option Heavy Reactive
        option Extreme Reactive
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 16 kHz)
        option Fast (downsample to 8 kHz)
    
    comment === Analysis ===
    positive Analysis_window_s 0.025
    positive Hop_size_s 0.025
    positive Smoothing_alpha 0.15
    
    comment === Dark Reverb (low entropy) ===
    positive Reverb_time_dark_s 2.5
    positive Damping_dark 0.8
    
    comment === Bright Reverb (high entropy) ===
    positive Reverb_time_bright_s 1.0
    positive Damping_bright 0.3
    
    comment === Dynamic Mix ===
    positive Min_wet_amount 0.1
    positive Max_wet_amount 0.9
    boolean Invert_mapping 0
    
    comment === Overall Mix ===
    real Wet_dry_percent 70
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

startTime = stopwatch

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
origSR = Get sampling frequency
numChannels = Get number of channels

# Private zero-based processing copy; the caller's original Sound is untouched.
selectObject: original
workSource = Copy: "entropy_reverb_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 2
    # Subtle Reactive
    analysis_window_s = 0.03
    hop_size_s = 0.03
    smoothing_alpha = 0.2
    reverb_time_dark_s = 1.8
    damping_dark = 0.7
    reverb_time_bright_s = 0.8
    damping_bright = 0.25
    min_wet_amount = 0.15
    max_wet_amount = 0.6
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Reactive
    analysis_window_s = 0.025
    hop_size_s = 0.025
    smoothing_alpha = 0.15
    reverb_time_dark_s = 2.5
    damping_dark = 0.8
    reverb_time_bright_s = 1.0
    damping_bright = 0.3
    min_wet_amount = 0.1
    max_wet_amount = 0.9
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Reactive
    analysis_window_s = 0.02
    hop_size_s = 0.02
    smoothing_alpha = 0.1
    reverb_time_dark_s = 3.5
    damping_dark = 0.85
    reverb_time_bright_s = 1.2
    damping_bright = 0.35
    min_wet_amount = 0.2
    max_wet_amount = 0.95
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Reactive
    analysis_window_s = 0.015
    hop_size_s = 0.015
    smoothing_alpha = 0.08
    reverb_time_dark_s = 4.5
    damping_dark = 0.9
    reverb_time_bright_s = 0.6
    damping_bright = 0.2
    min_wet_amount = 0.05
    max_wet_amount = 1.0
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Internal guards; preset values are already within these limits.
smoothing_alpha = min(1, max(0, smoothing_alpha))

min_wet_amount = min(1, max(0, min_wet_amount))
max_wet_amount = min(1, max(0, max_wet_amount))
if min_wet_amount > max_wet_amount
    tmpWet = min_wet_amount
    min_wet_amount = max_wet_amount
    max_wet_amount = tmpWet
endif

# Speed mode
if speed_mode = 1
    analysisSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    analysisSR = 16000
    speedStr$ = "Balanced"
else
    analysisSR = 8000
    speedStr$ = "Fast"
endif

# Clamp overall wet/dry
overall_wet = min(1, max(0, wet_dry_percent / 100))
overall_dry = 1 - overall_wet

# === Info ===
clearinfo
writeInfoLine: "=== Entropy-Modulated Reverb v2.2 COMPATIBLE ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: ""
appendInfoLine: "Dark reverb: ", reverb_time_dark_s, "s, damping=", damping_dark
appendInfoLine: "Bright reverb: ", reverb_time_bright_s, "s, damping=", damping_bright
appendInfoLine: "Overall wet/dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# STAGE 1: DOWNSAMPLE FOR ANALYSIS (SPEED OPTIMIZATION)
# ============================================================
appendInfo: "Stage 1: Preparing analysis... "

analysisSound = workSource
if analysisSR > 0 and origSR > analysisSR
    selectObject: workSource
    Resample: analysisSR, 50
    analysisSound = selected("Sound")
    sr = analysisSR
    appendInfoLine: "downsampled to ", analysisSR, " Hz"
else
    sr = origSR
    appendInfoLine: "using original SR"
endif

# ============================================================
# STAGE 2: COMPUTE SPECTRAL ENTROPY (OPTIMIZED)
# ============================================================
appendInfo: "Stage 2: Computing entropy... "

selectObject: analysisSound

# OPTIMIZATION: Reduce max frequency (don't need 5000 Hz for entropy)
maxFreq = min(3000, sr / 2)

To Spectrogram: analysis_window_s, maxFreq, hop_size_s, 20, "Gaussian"
spec = selected("Spectrogram")

num_frames = Get number of frames

# Pre-allocate arrays
entropyTime# = zero#(num_frames)
entropyVal# = zero#(num_frames)

# OPTIMIZED ENTROPY COMPUTATION
for iframe from 1 to num_frames
    selectObject: spec
    time = Get time from frame number: iframe
    entropyTime#[iframe] = time
    
    To Spectrum (slice): time
    spectrum = selected("Spectrum")
    
    num_bins = Get number of bins
    
    # OPTIMIZATION: Single-pass entropy calculation
    total_power = 0
    entropy = 0
    
    # Calculate power and entropy in one pass
    for ibin from 1 to num_bins
        re = Get real value in bin: ibin
        im = Get imaginary value in bin: ibin
        power = re * re + im * im
        total_power = total_power + power
    endfor
    
    # Compute entropy
    if total_power > 0
        for ibin from 1 to num_bins
            re = Get real value in bin: ibin
            im = Get imaginary value in bin: ibin
            power = re * re + im * im
            p = power / total_power
            if p > 0.0000001
                entropy = entropy - p * ln(p) / ln(2)
            endif
        endfor
        if num_bins > 1
            max_entropy = ln(num_bins) / ln(2)
            entropyVal#[iframe] = entropy / max_entropy
        else
            entropyVal#[iframe] = 0
        endif
    else
        entropyVal#[iframe] = 0
    endif
    
    removeObject: spectrum
    
    if iframe mod 50 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " ", num_frames, " frames"

# ============================================================
# STAGE 3: SMOOTH ENTROPY
# ============================================================
appendInfo: "Stage 3: Smoothing... "

# Exponential smoothing
prev_val = entropyVal#[1]
for i from 2 to num_frames
    curr_val = entropyVal#[i]
    smoothed = smoothing_alpha * curr_val + (1 - smoothing_alpha) * prev_val
    entropyVal#[i] = smoothed
    prev_val = smoothed
endfor

# OPTIMIZATION: Create entropy sound directly from array (faster than formula parts)
Create Sound from formula: "entropy_sound", 1, 0, originalDur, sr, "0"
entropySnd = selected("Sound")

# Fill with step-interpolated values (faster than linear interpolation per segment)
selectObject: entropySnd
numSamples = Get number of samples

for s from 1 to numSamples
    t = (s - 0.5) / sr
    
    # Find nearest frame
    frameIdx = round(t / hop_size_s) + 1
    frameIdx = max(1, min(num_frames, frameIdx))
    
    val = entropyVal#[frameIdx]
    Set value at sample number: 1, s, val
endfor

appendInfoLine: "done"

# ============================================================
# STAGE 4: CREATE REVERB IMPULSE RESPONSES
# ============================================================
appendInfo: "Stage 4: Creating reverb IRs... "

# FIX v2.1: Use origSR instead of sr to ensure convolution compatibility
# Dark IR (long decay, more damping)
Create Sound from formula: "ir_dark", 1, 0, reverb_time_dark_s, origSR, 
... "randomGauss(0,1) * exp(-x*5/" + string$(reverb_time_dark_s) + ") * exp(-x*" + string$(damping_dark) + "*10/" + string$(reverb_time_dark_s) + ")"
irDark = selected("Sound")
selectObject: irDark
irDarkPeak = Get absolute extremum: 0, 0, "None"
if irDarkPeak > 0
    Scale peak: 0.9
endif

# Bright IR (short decay, less damping)
Create Sound from formula: "ir_bright", 1, 0, reverb_time_bright_s, origSR, 
... "randomGauss(0,1) * exp(-x*8/" + string$(reverb_time_bright_s) + ") * exp(-x*" + string$(damping_bright) + "*3/" + string$(reverb_time_bright_s) + ")"
irBright = selected("Sound")
selectObject: irBright
irBrightPeak = Get absolute extremum: 0, 0, "None"
if irBrightPeak > 0
    Scale peak: 0.9
endif

appendInfoLine: "done"

# ============================================================
# STAGE 5: CONVOLVE
# ============================================================
appendInfo: "Stage 5: Convolving... "

selectObject: workSource, irDark
Convolve: "sum", "zero"
reverbDark = selected("Sound")
selectObject: reverbDark
reverbDarkPeak = Get absolute extremum: 0, 0, "None"
if reverbDarkPeak > 0
    Scale peak: 0.95
endif

selectObject: workSource, irBright
Convolve: "sum", "zero"
reverbBright = selected("Sound")
selectObject: reverbBright
reverbBrightPeak = Get absolute extremum: 0, 0, "None"
if reverbBrightPeak > 0
    Scale peak: 0.95
endif

# Mix over the longer convolution. Built-in presets already have dark >= bright.
selectObject: reverbDark
darkDur = Get total duration
selectObject: reverbBright
brightDur = Get total duration
maxDur = max(darkDur, brightDur)

appendInfoLine: "done"

# ============================================================
# STAGE 6: DYNAMIC MIXING (OPTIMIZED)
# ============================================================
appendInfo: "Stage 6: Mixing... "

# Resample entropy to original SR if needed
if analysisSR > 0 and origSR > analysisSR
    selectObject: entropySnd
    Resample: origSR, 50
    entResampled = selected("Sound")
    removeObject: entropySnd
    entropySnd = entResampled
endif

# Extend controls and dry signal explicitly to the longer reverb duration.
# Out-of-range object[] cells evaluate as zero.
dryExt = Create Sound from formula: "entropy_dry_extended", numChannels, 0, maxDur, origSR, "0"
workID$ = string$(workSource)
selectObject: dryExt
Formula: "object[" + workID$ + ", row, col]"

entExt = Create Sound from formula: "entropy_control_extended", 1, 0, maxDur, origSR, "0"
entropyID$ = string$(entropySnd)
selectObject: entExt
Formula: "object[" + entropyID$ + ", 1, col]"

# Use object IDs so same-named caller objects cannot redirect Formula reads.
darkID$ = string$(reverbDark)
brightID$ = string$(reverbBright)
dryID$ = string$(dryExt)
entID$ = string$(entExt)

# Create wet amount signal based on entropy
selectObject: entExt
Copy: "wet_amount"
wetAmount = selected("Sound")

if invert_mapping = 0
    # Low entropy -> more wet (warm reverb)
    Formula: string$(min_wet_amount) + " + (1 - self) * " + string$(max_wet_amount - min_wet_amount)
else
    # High entropy -> more wet
    Formula: string$(min_wet_amount) + " + self * " + string$(max_wet_amount - min_wet_amount)
endif

selectObject: wetAmount
wetID$ = string$(wetAmount)

# OPTIMIZED: Create output with single formula
selectObject: dryExt
Copy: originalName$ + "_entropyReverb_" + presetName$
result = selected("Sound")

# Mix formula (optimized single-pass):
# wet_reverb = (dark*(1-ent) + bright*ent)*wetAmount
# output = dry*(1-wetAmount) + wet_reverb
# Then apply overall wet/dry

selectObject: result
Formula: "object[" + dryID$ + ", row, col] * (1 - object[" + wetID$ + ", 1, col])"
    ... + " + (object[" + darkID$ + ", row, col] * (1 - object[" + entID$ + ", 1, col])"
    ... + " + object[" + brightID$ + ", row, col] * object[" + entID$ + ", 1, col])"
    ... + " * object[" + wetID$ + ", 1, col]"

# Apply overall wet/dry
if overall_dry > 0
    Formula: "self * " + string$(overall_wet)
        ... + " + object[" + dryID$ + ", row, col] * " + string$(overall_dry)
endif

resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > 0
    Scale peak: 0.95
endif

processingTime = stopwatch - startTime

appendInfoLine: "done"
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Entropy-Modulated Reverb: " + originalName$ + " [" + presetName$ + "]" + " | v0.4.1"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.3
    Select inner viewport: 0.60, 7.70, 0.7, 1.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.7, 1.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.7, 1.2
    Axes: 0, 1, 0, 1
    
    # Result waveform
    Select outer viewport: 0, 8, 1.4, 2.1
    Select inner viewport: 0.60, 7.70, 1.5, 2.0
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.5, 2.0
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Result"
    Select inner viewport: 0.60, 7.70, 1.5, 2.0
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    
    # Entropy curve
    Select outer viewport: 0, 8, 2.3, 3.5
    Select inner viewport: 0.60, 7.70, 2.4, 3.4
    
    Axes: 0, originalDur, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, originalDur, 0, 1.1
    
    # Draw entropy (subsample for speed) - FIXED for older Praat versions
    Colour: "{0.7, 0.5, 0.6}"
    Line width: 2
    
    step = max(1, floor(num_frames / 500))
    
    # FIX v2.2: Use while loop instead of 'for...by' to support older Praat
    i = step
    while i <= num_frames
        if i > step and entropyTime#[i-step] < originalDur
            Draw line: entropyTime#[i-step], entropyVal#[i-step], entropyTime#[i], entropyVal#[i]
        endif
        i = i + step
    endwhile
    
    Line width: 1
    
    # Reference lines
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0.5, originalDur, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.4, 3.4
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Entropy"
    Select inner viewport: 0.60, 7.70, 2.4, 3.4
    Axes: 0, originalDur, 0, 1.1
    Text bottom: "yes", "Time (s)"
    
    # Labels
    Font size: 6
    Colour: "{0.5, 0.5, 0.5}"
    Text: originalDur * 0.02, "left", 0.1, "half", "Tonal (dark reverb)"
    Text: originalDur * 0.02, "left", 0.95, "half", "Noisy (bright reverb)"
    
    # Dark/Bright IR comparison
    Select outer viewport: 0, 4, 3.7, 4.6
    Select inner viewport: 0.60, 3.85, 3.8, 4.5
    selectObject: irDark
    Colour: "{0.6, 0.5, 0.5}"
    Draw: 0, min(1.5, reverb_time_dark_s), 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 3.8, 4.5
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dark IR"
    Select inner viewport: 0.60, 3.85, 3.8, 4.5
    Axes: 0, originalDur, 0, 1.1
    
    Select outer viewport: 4, 8, 3.7, 4.6
    Select inner viewport: 4.45, 7.70, 3.8, 4.5
    selectObject: irBright
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, min(1.5, reverb_time_bright_s), 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 3.8, 4.5
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Bright IR"
    Select inner viewport: 4.45, 7.70, 3.8, 4.5
    Axes: 0, originalDur, 0, 1.1
    
    # Parameters
    Select outer viewport: 0, 8, 4.7, 5.1
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", speedStr$ + " | Time: " + fixed$(processingTime, 2) + "s | Dark: " + fixed$(reverb_time_dark_s, 1) + "s | Bright: " + fixed$(reverb_time_bright_s, 1) + "s | Overall: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, 5.20, 6.20
    Select inner viewport: 0.60, 7.70, 5.27, 6.13
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Entropy modulation controls the realized reverb-density trajectory"
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Read the diagram as processing structure, not as a generic envelope"

    # Restore full-page viewport before leaving visualization.
    Select inner viewport: 0.60, 7.70, 5.27, 6.13
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 6.30
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: spec
if analysisSound <> workSource
    removeObject: analysisSound
endif
removeObject: entropySnd, irDark, irBright
removeObject: reverbDark, reverbBright
removeObject: dryExt, entExt, wetAmount
removeObject: workSource

# === Final Info ===
selectObject: result

appendInfoLine: "Output: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: original
