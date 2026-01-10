# ============================================================
# Praat AudioTools - Entropy_Modulated_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
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
# Changelog v0.2:
#   - Added input check
#   - Fixed name-based references (use object IDs)
#   - Added presets
#   - Added overall wet/dry control
#   - Added visualization
# ============================================================

form Entropy-Modulated Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Reactive
        option Medium Reactive
        option Heavy Reactive
        option Extreme Reactive
    
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

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency

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

# Clamp overall wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

overall_wet = wet_dry_percent / 100
overall_dry = 1 - overall_wet

# === Info ===
writeInfoLine: "=== Entropy-Modulated Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis window: ", fixed$(analysis_window_s * 1000, 1), " ms"
appendInfoLine: "Smoothing alpha: ", smoothing_alpha
appendInfoLine: "Dark reverb: ", reverb_time_dark_s, "s, damping=", damping_dark
appendInfoLine: "Bright reverb: ", reverb_time_bright_s, "s, damping=", damping_bright
appendInfoLine: "Dynamic wet range: ", min_wet_amount, " - ", max_wet_amount
appendInfoLine: "Overall wet/dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# STEP 1: COMPUTE SPECTRAL ENTROPY
# ============================================================

appendInfoLine: "Step 1/5: Computing spectral entropy..."

selectObject: original
To Spectrogram: analysis_window_s, 5000, hop_size_s, 20, "Gaussian"
spec = selected("Spectrogram")

num_frames = Get number of frames

Create TableOfReal: "entropy_raw", num_frames, 2
tableRaw = selected("TableOfReal")

# Compute entropy for each frame
for iframe from 1 to num_frames
    selectObject: spec
    time = Get time from frame number: iframe
    
    To Spectrum (slice): time
    spectrum = selected("Spectrum")
    
    num_bins = Get number of bins
    total_power = 0
    
    # First pass: total power
    for ibin from 1 to num_bins
        re = Get real value in bin: ibin
        im = Get imaginary value in bin: ibin
        power = re * re + im * im
        total_power = total_power + power
    endfor
    
    # Second pass: entropy
    entropy = 0
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
        max_entropy = ln(num_bins) / ln(2)
        entropy = entropy / max_entropy
    endif
    
    selectObject: tableRaw
    Set value: iframe, 1, time
    Set value: iframe, 2, entropy
    
    removeObject: spectrum
endfor

# ============================================================
# STEP 2: SMOOTH ENTROPY (Exponential smoothing)
# ============================================================

appendInfoLine: "Step 2/5: Smoothing entropy curve..."

selectObject: tableRaw
prev_val = Get value: 1, 2

for i from 2 to num_frames
    curr_val = Get value: i, 2
    smoothed = smoothing_alpha * curr_val + (1 - smoothing_alpha) * prev_val
    Set value: i, 2, smoothed
    prev_val = smoothed
endfor

# Store entropy values for visualization
for i from 1 to num_frames
    selectObject: tableRaw
    entropyTime[i] = Get value: i, 1
    entropyVal[i] = Get value: i, 2
endfor

# Create entropy as Sound for mixing
Create Sound from formula: "entropy_sound", 1, 0, originalDur, sr, "0"
entropySnd = selected("Sound")

# Fill with interpolated entropy values
for i from 1 to num_frames - 1
    t1 = entropyTime[i]
    t2 = entropyTime[i + 1]
    v1 = entropyVal[i]
    v2 = entropyVal[i + 1]
    
    t1_str$ = string$(t1)
    t2_str$ = string$(t2)
    v1_str$ = string$(v1)
    v2_str$ = string$(v2)
    
    # Linear interpolation between points
    selectObject: entropySnd
    Formula (part): t1, t2, 1, 1, v1_str$ + " + (x - " + t1_str$ + ") / (" + t2_str$ + " - " + t1_str$ + ") * (" + v2_str$ + " - " + v1_str$ + ")"
endfor

# ============================================================
# STEP 3: CREATE REVERB IMPULSE RESPONSES
# ============================================================

appendInfoLine: "Step 3/5: Creating reverb IRs..."

# Dark IR (long decay, more damping)
dark_time_str$ = string$(reverb_time_dark_s)
dark_damp_str$ = string$(damping_dark)

Create Sound from formula: "ir_dark", 1, 0, reverb_time_dark_s, sr, "randomGauss(0,1) * exp(-x*5/" + dark_time_str$ + ") * exp(-x*" + dark_damp_str$ + "*10/" + dark_time_str$ + ")"
irDark = selected("Sound")
Scale peak: 0.9

# Bright IR (short decay, less damping)
bright_time_str$ = string$(reverb_time_bright_s)
bright_damp_str$ = string$(damping_bright)

Create Sound from formula: "ir_bright", 1, 0, reverb_time_bright_s, sr, "randomGauss(0,1) * exp(-x*8/" + bright_time_str$ + ") * exp(-x*" + bright_damp_str$ + "*3/" + bright_time_str$ + ")"
irBright = selected("Sound")
Scale peak: 0.9

# ============================================================
# STEP 4: CONVOLVE
# ============================================================

appendInfoLine: "Step 4/5: Convolving..."

selectObject: original, irDark
Convolve: "sum", "zero"
reverbDark = selected("Sound")
Scale peak: 0.95

selectObject: original, irBright
Convolve: "sum", "zero"
reverbBright = selected("Sound")
Scale peak: 0.95

# Get max duration
selectObject: reverbDark
maxDur = Get total duration

# ============================================================
# STEP 5: DYNAMIC MIXING
# ============================================================

appendInfoLine: "Step 5/5: Dynamic mixing..."

# Extend/trim all to same length
selectObject: original
Extract part: 0, maxDur, "rectangular", 1, "yes"
dryExt = selected("Sound")

selectObject: reverbBright
Extract part: 0, maxDur, "rectangular", 1, "yes"
brightExt = selected("Sound")

selectObject: entropySnd
Extract part: 0, maxDur, "rectangular", 1, "yes"
entExt = selected("Sound")

# Build formula strings
minWet_str$ = string$(min_wet_amount)
maxWet_str$ = string$(max_wet_amount)
overallWet_str$ = string$(overall_wet)
overallDry_str$ = string$(overall_dry)

dark_str$ = string$(reverbDark)
bright_str$ = string$(brightExt)
dry_str$ = string$(dryExt)
ent_str$ = string$(entExt)

# Create wet amount signal based on entropy
selectObject: entExt
Copy: "wet_amount"
wetAmount = selected("Sound")

if invert_mapping = 0
    # Low entropy → more wet (warm reverb)
    Formula: minWet_str$ + " + (1 - self) * (" + maxWet_str$ + " - " + minWet_str$ + ")"
else
    # High entropy → more wet
    Formula: minWet_str$ + " + self * (" + maxWet_str$ + " - " + minWet_str$ + ")"
endif

wet_str$ = string$(wetAmount)

# Create output
selectObject: dryExt
Copy: "output_temp"
outputTemp = selected("Sound")

# Mix formula:
# output = dry*(1-wet) + (dark*(1-ent) + bright*ent)*wet
# Then apply overall wet/dry

Formula: "self * (1 - object[" + wet_str$ + "]) + (object[" + dark_str$ + "] * (1 - object[" + ent_str$ + "]) + object[" + bright_str$ + "] * object[" + ent_str$ + "]) * object[" + wet_str$ + "]"

# Apply overall wet/dry
if overall_dry > 0
    Formula: "self * " + overallWet_str$ + " + object[" + dry_str$ + "] * " + overallDry_str$
endif

selectObject: outputTemp
Scale peak: 0.95
Rename: originalName$ + "_entropyReverb_" + presetName$
result = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Entropy-Modulated Reverb: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.3
    Select inner viewport: 0.6, 7.6, 0.7, 1.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.4, 2.1
    Select inner viewport: 0.6, 7.6, 1.5, 2.0
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Entropy curve
    Select outer viewport: 0, 8, 2.3, 3.5
    Select inner viewport: 0.6, 7.6, 2.4, 3.4
    
    Axes: 0, originalDur, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, originalDur, 0, 1.1
    
    # Draw entropy
    Colour: "{0.7, 0.5, 0.6}"
    Line width: 2
    for i from 2 to num_frames
        if entropyTime[i-1] < originalDur and entropyTime[i] < originalDur
            Draw line: entropyTime[i-1], entropyVal[i-1], entropyTime[i], entropyVal[i]
        endif
    endfor
    Line width: 1
    
    # Reference lines
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0.5, originalDur, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Entropy"
    Text bottom: "yes", "Time (s)"
    
    # Labels
    Font size: 5
    Colour: "{0.5, 0.5, 0.5}"
    Text: originalDur * 0.02, "left", 0.1, "half", "Tonal (dark reverb)"
    Text: originalDur * 0.02, "left", 0.95, "half", "Noisy (bright reverb)"
    
    # Dark/Bright IR comparison
    Select outer viewport: 0, 4, 3.7, 4.6
    Select inner viewport: 0.6, 3.8, 3.8, 4.5
    selectObject: irDark
    Colour: "{0.6, 0.5, 0.5}"
    Draw: 0, min(1.5, reverb_time_dark_s), 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Dark IR"
    
    Select outer viewport: 4, 8, 3.7, 4.6
    Select inner viewport: 4.4, 7.6, 3.8, 4.5
    selectObject: irBright
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, min(1.5, reverb_time_bright_s), 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Bright IR"
    
    # Parameters
    Select outer viewport: 0, 8, 4.7, 5.1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Dark: " + fixed$(reverb_time_dark_s, 1) + "s | Bright: " + fixed$(reverb_time_bright_s, 1) + "s | Wet range: " + fixed$(min_wet_amount, 2) + "-" + fixed$(max_wet_amount, 2) + " | Overall: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: spec, tableRaw
removeObject: entropySnd, irDark, irBright
removeObject: reverbDark, reverbBright
removeObject: dryExt, brightExt, entExt, wetAmount

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result