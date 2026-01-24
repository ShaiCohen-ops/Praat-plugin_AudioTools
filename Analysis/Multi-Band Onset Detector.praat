# ============================================================
# Praat AudioTools - Multi-Band Onset Detector.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-band onset detector for transient/sustain separation.
#   Analyzes energy increases across frequency bands to detect
#   attacks and onsets. Separates audio into transient (percussive)
#   and sustain (tonal) components for spectromorphological analysis.
#
# Changelog v0.2:
#   - Added visualization (waveforms, onset function, mask)
#   - Added presets for different material types
#   - Added band energy display
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

# ===== CONFIGURATION =====
form Multi-Band Onset Detector
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Drums/Percussion
        option Piano/Plucked
        option Voice/Speech
        option Full Mix
        option Soft Transients
    comment === Detection Parameters ===
    real Transient_threshold_(dB) -30
    real Attack_window_(ms) 20
    real Release_window_(ms) 50
    comment === Frequency Range ===
    real Low_frequency_(Hz) 100
    real High_frequency_(Hz) 8000
    integer Number_of_bands 4
    comment === Performance ===
    real Working_sample_rate_(Hz) 8000
    comment === Output Options ===
    boolean Create_transient_sound 1
    boolean Create_sustain_sound 1
    boolean Swap_outputs_for_speech 0
    boolean Normalize_outputs 1
    real Peak_amplitude 0.99
    comment === Display ===
    boolean Show_visualization 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Drums/Percussion
    transient_threshold = -25
    attack_window = 10
    release_window = 30
    low_frequency = 50
    high_frequency = 12000
    number_of_bands = 5
    presetName$ = "DrumPerc"
elsif preset = 3
    # Piano/Plucked
    transient_threshold = -35
    attack_window = 15
    release_window = 80
    low_frequency = 80
    high_frequency = 8000
    number_of_bands = 4
    presetName$ = "PianoPlucked"
elsif preset = 4
    # Voice/Speech
    transient_threshold = -30
    attack_window = 25
    release_window = 40
    low_frequency = 100
    high_frequency = 6000
    number_of_bands = 4
    swap_outputs_for_speech = 1
    presetName$ = "VoiceSpeech"
elsif preset = 5
    # Full Mix
    transient_threshold = -28
    attack_window = 20
    release_window = 60
    low_frequency = 50
    high_frequency = 16000
    number_of_bands = 6
    presetName$ = "FullMix"
elsif preset = 6
    # Soft Transients
    transient_threshold = -40
    attack_window = 30
    release_window = 100
    low_frequency = 100
    high_frequency = 8000
    number_of_bands = 4
    presetName$ = "SoftTransients"
else
    presetName$ = "Custom"
endif

# ===== INITIAL CHECKS =====
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds = 0
    exitScript: "Error: Please select a Sound object first"
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")
selectObject: original_sound
duration = Get total duration
original_sampleRate = Get sampling frequency
n_channels = Get number of channels

writeInfoLine: "=== Multi-Band Onset Detector v0.2 ==="
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Original: ", n_channels, " ch, ", original_sampleRate, " Hz"
appendInfoLine: ""

# ===== PREPROCESSING: MONO + DOWNSAMPLE =====
appendInfoLine: "Preprocessing..."

selectObject: original_sound

# Convert to mono if needed
if n_channels > 1
    appendInfoLine: "  Converting to mono..."
    mono_sound = Convert to mono
else
    mono_sound = original_sound
endif

# Downsample for speed
if working_sample_rate > 0 and working_sample_rate < original_sampleRate
    appendInfoLine: "  Downsampling to ", working_sample_rate, " Hz..."
    selectObject: mono_sound
    working_sound = Resample: working_sample_rate, 50
    sampleRate = working_sample_rate
    if mono_sound <> original_sound
        removeObject: mono_sound
    endif
else
    working_sound = mono_sound
    sampleRate = original_sampleRate
endif

selectObject: working_sound
n_samples = Get number of samples

appendInfoLine: "  Working: ", sampleRate, " Hz, ", n_samples, " samples"

if swap_outputs_for_speech
    appendInfoLine: "  Mode: SPEECH (outputs swapped)"
else
    appendInfoLine: "  Mode: MUSIC (normal)"
endif
appendInfoLine: ""

# ===== STEP 1: MULTI-BAND FILTERING =====
appendInfoLine: "Step 1: Creating ", number_of_bands, "-band filterbank..."

# Logarithmic band spacing
for i from 0 to number_of_bands
    band_edge[i] = low_frequency * (high_frequency / low_frequency) ^ (i / number_of_bands)
endfor

# Create combined envelope initialized to zero
selectObject: working_sound
combined_envelope = Copy: "combined_env"
Formula: "0"

# Store band envelopes for visualization
for i from 1 to number_of_bands
    appendInfoLine: "  Band ", i, "/", number_of_bands, ": ", fixed$(band_edge[i-1], 0), "-", fixed$(band_edge[i], 0), " Hz"
    
    # Filter
    selectObject: working_sound
    filtered = Filter (pass Hann band): band_edge[i-1], band_edge[i], 100
    
    # Rectify
    Formula: "abs(self)"
    
    # Smooth (envelope)
    smooth = Filter (pass Hann band): 0, 50, 20
    smooth_id = selected("Sound")
    
    # Store for visualization (first 3 bands only to save memory)
    if i <= 3 and show_visualization
        selectObject: smooth
        band_env[i] = Copy: "band_" + string$(i)
    endif
    
    # Add to combined envelope using explicit ID
    selectObject: combined_envelope
    combined_id = selected("Sound")
    Formula: "self + object[smooth_id]"
    
    removeObject: filtered, smooth
endfor

# Store combined envelope for visualization
if show_visualization
    selectObject: combined_envelope
    combined_env_viz = Copy: "combined_env_viz"
endif

# ===== STEP 2: COMPUTE ONSET FUNCTION (DERIVATIVE) =====
appendInfoLine: ""
appendInfoLine: "Step 2: Computing onset function..."

selectObject: combined_envelope
onset_function = Copy: "onset_func"

# Differentiate using formula (much faster than loop!)
Formula: "if col > 1 then max(0, self - self[col-1]) else 0 endif"

# Store for visualization
if show_visualization
    selectObject: onset_function
    onset_func_viz = Copy: "onset_func_viz"
endif

max_onset = Get maximum: 0, 0, "None"
threshold_linear = 10^(transient_threshold / 20) * max_onset

appendInfoLine: "  Max onset: ", fixed$(max_onset, 6)
appendInfoLine: "  Threshold: ", fixed$(threshold_linear, 6)

# ===== STEP 3: CREATE TRANSIENT MASK =====
appendInfoLine: ""
appendInfoLine: "Step 3: Creating onset mask..."

selectObject: onset_function
transient_mask = Copy: "trans_mask"

# Simple threshold to binary mask
Formula: "if self > threshold_linear then 1 else 0 endif"

# Expand mask with attack/release windows
attack_samples = round((attack_window / 1000) * sampleRate)
release_samples = round((release_window / 1000) * sampleRate)

# Dilate mask (expand regions)
total_window = attack_samples + release_samples

if total_window > 0
    # Create smoothing window
    window_dur = total_window / sampleRate
    Create Sound from formula: "smooth_window", 1, 0, window_dur, sampleRate,
        ... "if x < attack_window/1000 then x/(attack_window/1000) else exp(-5*(x-attack_window/1000)/(release_window/1000)) endif"
    smooth_win = selected("Sound")
    
    # Convolve mask with window (dilates and shapes)
    selectObject: transient_mask, smooth_win
    convolved = Convolve: "sum", "zero"
    
    # Clip to 0-1 range
    Formula: "if self > 1 then 1 else if self < 0 then 0 else self endif endif"
    
    removeObject: transient_mask, smooth_win
    transient_mask = convolved
    Rename: "trans_mask"
endif

# Store mask for visualization
if show_visualization
    selectObject: transient_mask
    mask_viz = Copy: "mask_viz"
endif

# ===== STEP 4: EXTRACT TRANSIENTS AND SUSTAIN =====
appendInfoLine: ""
appendInfoLine: "Step 4: Extracting components..."

mask_id = transient_mask

# Decide which output gets which based on swap setting
if swap_outputs_for_speech
    transient_formula$ = "self * (1 - object[mask_id])"
    sustain_formula$ = "self * object[mask_id]"
    transient_label$ = "_transients"
    sustain_label$ = "_sustain"
else
    transient_formula$ = "self * object[mask_id]"
    sustain_formula$ = "self * (1 - object[mask_id])"
    transient_label$ = "_transients"
    sustain_label$ = "_sustain"
endif

if create_transient_sound
    selectObject: working_sound
    transients_work = Copy: "trans_temp"
    Formula: transient_formula$
    
    # Store for visualization before resampling
    if show_visualization
        selectObject: transients_work
        transients_viz = Copy: "transients_viz"
    endif
    
    # Resample back if needed
    if working_sound <> mono_sound
        selectObject: transients_work
        transients = Resample: original_sampleRate, 50
        removeObject: transients_work
    else
        transients = transients_work
    endif
    
    Rename: original_name$ + transient_label$
    
    if normalize_outputs
        Scale peak: peak_amplitude
    endif
    
    appendInfoLine: "  Created transients"
endif

if create_sustain_sound
    selectObject: working_sound
    sustain_work = Copy: "sust_temp"
    Formula: sustain_formula$
    
    # Store for visualization before resampling
    if show_visualization
        selectObject: sustain_work
        sustain_viz = Copy: "sustain_viz"
    endif
    
    # Resample back if needed
    if working_sound <> mono_sound
        selectObject: sustain_work
        sustain = Resample: original_sampleRate, 50
        removeObject: sustain_work
    else
        sustain = sustain_work
    endif
    
    Rename: original_name$ + sustain_label$
    
    if normalize_outputs
        Scale peak: peak_amplitude
    endif
    
    appendInfoLine: "  Created sustain"
endif

# ===== VISUALIZATION =====
if show_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 1.5, 8, 0.3, 0.5
    Font size: 14
    Colour: "Black"
    Text: 2.0, "centre", 0.1, "half", "Multi-Band Onset Detector: " + original_name$ + " [" + presetName$ + "]"
    
    # --- Original waveform ---
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.5, 7.5, 0.7, 1.4
    
    selectObject: working_sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # --- Onset function with threshold ---
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.5, 7.5, 1.7, 2.4
    
    selectObject: onset_func_viz
    onset_max_viz = Get maximum: 0, 0, "None"
    if onset_max_viz <= 0
        onset_max_viz = 1
    endif
    
    Axes: 0, duration, 0, onset_max_viz * 1.1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, onset_max_viz * 1.1
    
    # Threshold line
    Colour: "{0.8, 0.3, 0.3}"
    Dotted line
    Draw line: 0, threshold_linear, duration, threshold_linear
    Solid line
    
    # Onset function
    Colour: "{0.2, 0.6, 0.8}"
    Line width: 1
    Draw: 0, 0, 0, onset_max_viz * 1.1, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Onset"
    
    # --- Transient mask ---
    Select outer viewport: 0, 8, 2.6, 3.3
    Select inner viewport: 0.5, 7.5, 2.7, 3.2
    
    selectObject: mask_viz
    Colour: "{0.8, 0.5, 0.2}"
    Draw: 0, 0, 0, 1.1, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mask"
    
    # --- Transients ---
    if create_transient_sound
        Select outer viewport: 0, 8, 3.4, 4.3
        Select inner viewport: 0.5, 7.5, 3.5, 4.2
        
        selectObject: transients_viz
        Colour: "{0.8, 0.3, 0.3}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Transient"
    endif
    
    # --- Sustain ---
    if create_sustain_sound
        Select outer viewport: 0, 8, 4.4, 5.3
        Select inner viewport: 0.5, 7.5, 4.5, 5.2
        
        selectObject: sustain_viz
        Colour: "{0.3, 0.6, 0.3}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Sustain"
        Text bottom: "yes", "Time (s)"
    endif
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 5.4, 5.8
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Threshold: " + string$(transient_threshold) + " dB | Attack: " + string$(attack_window) + " ms | Release: " + string$(release_window) + " ms | Bands: " + string$(number_of_bands) + " (" + string$(low_frequency) + "-" + string$(high_frequency) + " Hz)"
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup visualization objects
    removeObject: combined_env_viz, onset_func_viz, mask_viz
    if create_transient_sound
        removeObject: transients_viz
    endif
    if create_sustain_sound
        removeObject: sustain_viz
    endif
    for i from 1 to min(3, number_of_bands)
        removeObject: band_env[i]
    endfor
endif

# ===== CLEANUP =====
removeObject: combined_envelope, onset_function, transient_mask

if working_sound <> original_sound
    if working_sound <> mono_sound
        removeObject: working_sound
    endif
endif

# ===== SUMMARY =====
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: ""

if swap_outputs_for_speech
    appendInfoLine: "SPEECH MODE (swapped outputs):"
    appendInfoLine: "  - Transients = consonants, bursts, fricatives"
    appendInfoLine: "  - Sustain = vowels, sustained harmonics"
else
    appendInfoLine: "MUSIC MODE (normal):"
    appendInfoLine: "  - Transients = attacks, onsets, percussive events"
    appendInfoLine: "  - Sustain = resonances, sustained tones"
endif

appendInfoLine: ""
appendInfoLine: "Compositional applications:"
appendInfoLine: "  - Gesture vs. texture separation (spectromorphology)"
appendInfoLine: "  - Isolate attacks from sustained material"
appendInfoLine: "  - Morphological analysis of sound events"

# Select outputs
if create_transient_sound and create_sustain_sound
    selectObject: transients, sustain
elsif create_transient_sound
    selectObject: transients
elsif create_sustain_sound
    selectObject: sustain
endif