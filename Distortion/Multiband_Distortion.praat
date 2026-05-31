# ============================================================
# Praat AudioTools - Multiband_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - normalized drive (true distortion); re-tuned presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multiband Distortion - splits audio into Low, Mid, and High
#   frequency bands. Applies independent distortion type and drive
#   to each band (soft clip, hard clip, or wavefold). Recombines
#   using phase-coherent subtraction logic.
#
# Changelog v0.2:
#   - Modern procedure call syntax (@)
#   - Enhanced visualization with band indicators
#   - Improved info output
#
# Changelog v0.3:
#   - Oversampled (anti-aliased) processing: the band split + per-band
#     nonlinearities + sum now run at an integer multiple of the sample rate,
#     then the wet sum is resampled back. Praat's downsampling resampler
#     band-limits, removing the harmonics that otherwise fold back as aliasing
#     (worst on hard-clip / sine-fold at high drive on high-frequency content).
#   - Output_Gain now applies AFTER peak-normalization, so it is an effective
#     master trim at any Mix (previously the final Scale peak cancelled it at
#     Mix = 1).
#
# Changelog v0.4:
#   - Normalize_drive (default on): each band is scaled into the waveshaper by
#     its own peak before 'drive' is applied, then restored on the way out - so
#     drive distorts regardless of how quiet the band is. Previously the split
#     left bands too low to engage the nonlinearity, so the effect was mostly a
#     filter (e.g. hard clip at drive 3 on a band produced zero harmonics).
#     Toggle off for the legacy level-dependent behaviour.
#   - Preset drive values re-tuned for the normalized (much hotter) response.
# ============================================================

# === Form ===
form Multiband Distortion
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (use settings below)
        option Warm Bass / Clean Highs
        option Frizz (Distorted Highs Only)
        option V-Shape Destruction
        option Mid-Range Crunch (Telephone)
        option Full Spectrum Fuzz

    comment === Crossovers ===
    real Low_Split_Hz 200
    real High_Split_Hz 2500

    comment === Drive normalizes into the waveshaper (off = legacy level-dependent) ===
    boolean Normalize_drive 1

    comment === Low Band ===
    real Low_Drive 1.0
    optionmenu Low_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Fold
    real Low_Gain 1.0

    comment === Mid Band ===
    real Mid_Drive 1.0
    optionmenu Mid_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Fold
    real Mid_Gain 1.0

    comment === High Band ===
    real High_Drive 1.0
    optionmenu High_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Fold
    real High_Gain 1.0

    comment === Master ===
    real Mix_0_to_1 1.0
    real Output_Gain 0.9
    
    comment === Anti-aliasing (oversample factor; 1 = off) ===
    integer Oversample 4

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
duration = Get total duration
sr = Get sampling frequency

# Oversampling factor (anti-aliasing); clamp to a sane range
if oversample < 1
    oversample = 1
endif
if oversample > 8
    oversample = 8
endif

# === Handle Presets ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "WarmBass"
    low_Drive = 2.0
    low_Type = 1
    low_Gain = 1.1
    mid_Drive = 1.0
    mid_Type = 1
    high_Drive = 0.8
    high_Type = 1
elsif preset = 3
    presetName$ = "Frizz"
    low_Drive = 1.0
    low_Type = 1
    mid_Drive = 1.0
    mid_Type = 1
    high_Drive = 3.5
    high_Type = 2
    high_Split_Hz = 1500
elsif preset = 4
    presetName$ = "VShape"
    low_Drive = 2.5
    low_Type = 2
    mid_Drive = 1.0
    mid_Type = 1
    mid_Gain = 0.7
    high_Drive = 2.5
    high_Type = 2
elsif preset = 5
    presetName$ = "MidCrunch"
    low_Split_Hz = 400
    high_Split_Hz = 3000
    low_Drive = 0.6
    low_Gain = 0.5
    mid_Drive = 3.0
    mid_Type = 3
    mid_Gain = 1.2
    high_Drive = 0.6
    high_Gain = 0.5
elsif preset = 6
    presetName$ = "FullFuzz"
    low_Drive = 3.0
    mid_Drive = 3.0
    high_Drive = 3.0
    low_Type = 2
    mid_Type = 2
    high_Type = 2
endif

# Safety check for crossovers
if low_Split_Hz >= high_Split_Hz
    temp = low_Split_Hz
    low_Split_Hz = high_Split_Hz - 1
    high_Split_Hz = temp + 1
endif

# Get type names
if low_Type = 1
    lowTypeName$ = "Soft"
elsif low_Type = 2
    lowTypeName$ = "Hard"
else
    lowTypeName$ = "Fold"
endif

if mid_Type = 1
    midTypeName$ = "Soft"
elsif mid_Type = 2
    midTypeName$ = "Hard"
else
    midTypeName$ = "Fold"
endif

if high_Type = 1
    highTypeName$ = "Soft"
elsif high_Type = 2
    highTypeName$ = "Hard"
else
    highTypeName$ = "Fold"
endif

# === Info ===
writeInfoLine: "=== Multiband Distortion ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Crossovers: ", low_Split_Hz, " / ", high_Split_Hz, " Hz"
appendInfoLine: ""
appendInfoLine: "Low (<", low_Split_Hz, " Hz): ", lowTypeName$, " @ ", low_Drive, "x, gain ", low_Gain
appendInfoLine: "Mid (", low_Split_Hz, "-", high_Split_Hz, " Hz): ", midTypeName$, " @ ", mid_Drive, "x, gain ", mid_Gain
appendInfoLine: "High (>", high_Split_Hz, " Hz): ", highTypeName$, " @ ", high_Drive, "x, gain ", high_Gain
appendInfoLine: ""

# ============================================================
# STEP 1: CROSSOVER SPLIT (Phase-Coherent)
# ============================================================

appendInfoLine: "Splitting into bands..."

# Working signal for the aliasing-prone split + distortion + sum stage.
# Oversample so the nonlinearities' harmonics have headroom; the summed
# result is downsampled afterwards (the resampler band-limits on the way down).
if oversample > 1
    selectObject: original
    workSig = Resample: sr * oversample, 50
else
    selectObject: original
    workSig = Copy: "Proc_Temp"
endif

# 1. Create Total Low Pass (Temp)
selectObject: workSig
Filter (pass Hann band): 0, high_Split_Hz, 20
Rename: "LP_Total_Temp"
lp_Total_Obj = selected("Sound")

# 2. Create Low Band
selectObject: workSig
Filter (pass Hann band): 0, low_Split_Hz, 20
Rename: "Low_Band"
low_Obj = selected("Sound")

# 3. Create Mid Band (LP_Total - Low)
selectObject: lp_Total_Obj
Copy: "Mid_Band"
mid_Obj = selected("Sound")
Formula: ~ self - object[low_Obj]

# 4. Create High Band (Proc - LP_Total)
selectObject: workSig
Copy: "High_Band"
high_Obj = selected("Sound")
Formula: ~ self - object[lp_Total_Obj]

# Cleanup temp objects
removeObject: lp_Total_Obj, workSig

# ============================================================
# STEP 2: APPLY DISTORTION PER BAND
# ============================================================

appendInfoLine: "Applying distortion..."

# --- LOW BAND ---
selectObject: low_Obj
@applyDistortion: low_Drive, low_Type, low_Gain

# --- MID BAND ---
selectObject: mid_Obj
@applyDistortion: mid_Drive, mid_Type, mid_Gain

# --- HIGH BAND ---
selectObject: high_Obj
@applyDistortion: high_Drive, high_Type, high_Gain

# ============================================================
# STEP 3: SUM AND MIX
# ============================================================

appendInfoLine: "Summing bands..."

# Sum the bands (Wet Signal)
selectObject: low_Obj
Copy: "Wet_Sum_Temp"
wet_Obj = selected("Sound")
Formula: ~ self + object[mid_Obj] + object[high_Obj]

# CLEANUP: Remove the bands
removeObject: low_Obj, mid_Obj, high_Obj

# Downsample the wet sum back to the original rate (anti-aliased)
if oversample > 1
    selectObject: wet_Obj
    wet_Down = Resample: sr, 50
    removeObject: wet_Obj
    wet_Obj = wet_Down
endif

# Handle Mix (Output_Gain is applied later as a master trim)
if mix_0_to_1 >= 1.0
    # 100% Wet: Just rename the Wet object
    selectObject: wet_Obj
    Rename: origName$ + "_MultiDist_" + presetName$
    result = wet_Obj
else
    # Partial Mix: Create a Dry Copy and mix
    selectObject: original
    Copy: "Dry_Temp"
    dry_Obj = selected("Sound")
    
    wet_Mix = mix_0_to_1
    dry_Mix = 1.0 - mix_0_to_1
    
    # Mix into the Dry object
    Formula: ~ self * dry_Mix + object[wet_Obj] * wet_Mix
    
    Rename: origName$ + "_MultiDist_" + presetName$
    result = dry_Obj
    
    # CLEANUP: Remove the Wet object
    removeObject: wet_Obj
endif

# Normalize to a known peak, THEN apply the master Output Gain, so Output_Gain
# is an effective final trim at any Mix (final peak ~ 0.95 * Output_Gain).
selectObject: result
Scale peak: 0.95
Formula: ~ self * output_Gain

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Multiband Distortion: " + origName$ + " (" + presetName$ + ")"
    
    # === Original Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # === Result Waveform ===
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Processed"
    Text bottom: "yes", "Time (s)"
    
    # === Spectral Analysis ===
    Select outer viewport: 0, 8, 2.7, 4.3
    Select inner viewport: 0.6, 7.6, 2.8, 4.2
    
    # Get spectra
    selectObject: original
    spec_Orig = To Spectrum: "yes"
    selectObject: result
    spec_Res = To Spectrum: "yes"
    
    # Set dB range
    maxDB = 80
    minDB = 0
    
    # Determine frequency range
    maxFreq = sr / 2
    if maxFreq > 8000
        freqMax = 8000
    else
        freqMax = maxFreq
    endif
    
    Axes: 0, freqMax, minDB, maxDB
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, freqMax, minDB, maxDB
    
    # Shade band regions
    Paint rectangle: "{0.9, 0.85, 0.85}", 0, low_Split_Hz, minDB, maxDB
    Paint rectangle: "{0.85, 0.9, 0.85}", low_Split_Hz, min(high_Split_Hz, freqMax), minDB, maxDB
    Paint rectangle: "{0.85, 0.85, 0.9}", min(high_Split_Hz, freqMax), freqMax, minDB, maxDB
    
    # Draw Original (Grey)
    selectObject: spec_Orig
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 1
    Draw: 0, freqMax, minDB, maxDB, "no"
    
    # Draw Result (Red)
    selectObject: spec_Res
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1.5
    Draw: 0, freqMax, minDB, maxDB, "no"
    Line width: 1
    
    # Draw Crossover Lines
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 1.5
    if low_Split_Hz < freqMax
        Draw line: low_Split_Hz, minDB, low_Split_Hz, maxDB
    endif
    if high_Split_Hz < freqMax
        Draw line: high_Split_Hz, minDB, high_Split_Hz, maxDB
    endif
    Line width: 1
    
    # Box and labels
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Band labels at top
    Font size: 6
    Colour: "{0.6, 0.4, 0.4}"
    Text: low_Split_Hz / 2, "centre", maxDB - 5, "half", "LOW"
    Colour: "{0.4, 0.6, 0.4}"
    midCenter = (low_Split_Hz + min(high_Split_Hz, freqMax)) / 2
    Text: midCenter, "centre", maxDB - 5, "half", "MID"
    Colour: "{0.4, 0.4, 0.6}"
    if high_Split_Hz < freqMax
        highCenter = (high_Split_Hz + freqMax) / 2
        Text: highCenter, "centre", maxDB - 5, "half", "HIGH"
    endif
    
    # Cleanup Spectra
    removeObject: spec_Orig, spec_Res
    
    # === Band Settings Display ===
    Select outer viewport: 0, 8, 4.5, 5.3
    Select inner viewport: 0.6, 7.6, 4.6, 5.2
    
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 3, 0, 2
    
    # Low band info
    Paint rectangle: "{0.9, 0.85, 0.85}", 0, 1, 0, 2
    Font size: 6
    Colour: "{0.5, 0.3, 0.3}"
    Text: 0.5, "centre", 1.6, "half", "LOW"
    Text: 0.5, "centre", 1.2, "half", "<" + string$(low_Split_Hz) + " Hz"
    Text: 0.5, "centre", 0.8, "half", lowTypeName$ + " @ " + fixed$(low_Drive, 1) + "x"
    Text: 0.5, "centre", 0.4, "half", "Gain: " + fixed$(low_Gain, 1)
    
    # Mid band info
    Paint rectangle: "{0.85, 0.9, 0.85}", 1, 2, 0, 2
    Colour: "{0.3, 0.5, 0.3}"
    Text: 1.5, "centre", 1.6, "half", "MID"
    Text: 1.5, "centre", 1.2, "half", string$(low_Split_Hz) + "-" + string$(high_Split_Hz) + " Hz"
    Text: 1.5, "centre", 0.8, "half", midTypeName$ + " @ " + fixed$(mid_Drive, 1) + "x"
    Text: 1.5, "centre", 0.4, "half", "Gain: " + fixed$(mid_Gain, 1)
    
    # High band info
    Paint rectangle: "{0.85, 0.85, 0.9}", 2, 3, 0, 2
    Colour: "{0.3, 0.3, 0.5}"
    Text: 2.5, "centre", 1.6, "half", "HIGH"
    Text: 2.5, "centre", 1.2, "half", ">" + string$(high_Split_Hz) + " Hz"
    Text: 2.5, "centre", 0.8, "half", highTypeName$ + " @ " + fixed$(high_Drive, 1) + "x"
    Text: 2.5, "centre", 0.4, "half", "Gain: " + fixed$(high_Gain, 1)
    
    Colour: "Black"
    Draw inner box
    
    # === Master Info ===
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Mix: " + fixed$(mix_0_to_1 * 100, 0) + "% | Output Gain: " + fixed$(output_Gain, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result

# ============================================================
# PROCEDURE: Apply Distortion
# ============================================================
procedure applyDistortion: .drive, .type, .gain
    # Gain-staging. If Normalize_drive is on, scale the band UP into the
    # waveshaper by its own peak so 'drive' engages regardless of how quiet the
    # band is, then restore the level on the way out. Off = legacy behaviour
    # (input = self * drive), which barely distorts low-level bands.
    if normalize_drive
        .pk = Get absolute extremum: 0, 0, "None"
        if .pk <= 0
            .pk = 1
        endif
        .inScale = .drive / .pk
        .outScale = .gain * .pk
    else
        .inScale = .drive
        .outScale = .gain
    endif
    .is$ = string$(.inScale)
    .os$ = string$(.outScale)
    .nos$ = string$(-.outScale)

    if .type = 1
        # Soft Clip (Tanh)
        Formula: "tanh(self * " + .is$ + ") * " + .os$

    elsif .type = 2
        # Hard Clip - nested if/then/else (no elsif in formula language)
        .input$ = "(self * " + .is$ + ")"
        Formula: "if " + .input$ + " > 1 then " + .os$ + " else (if " + .input$ + " < -1 then " + .nos$ + " else " + .input$ + " * " + .os$ + " fi) fi"

    elsif .type = 3
        # Sine Fold
        Formula: "sin(self * " + .is$ + ") * " + .os$
    endif
endproc
