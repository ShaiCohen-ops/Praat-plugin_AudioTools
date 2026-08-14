# ============================================================
# Praat AudioTools - Time_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time Manipulation - PSOLA time-stretching with spectral blur
#   and stereo width effect. Uses pitch-preserving PSOLA for
#   natural time stretching, cascaded lowpass for ambient blur,
#   and delay/filtering for fake stereo width.
#
# Changelog v0.9:
#   - API compatibility: public form is byte-for-byte unchanged.
#   - Fixed true right-channel delay ordering (silence is prepended).
#   - Fixed possible L/R swap before stereo combination.
#   - Zero-based private work copy fixes non-zero source xmin.
#   - Hardened blur pass count and Nyquist-safe cutoffs.
#   - High Blur_amount values no longer silently stop adding passes.
#   - Safe peak normalization for non-silent output only.
#   - Spectrogram visualization uses mono analysis copies.
#   - Added duration and PSOLA pitch-range validation.
#
# Changelog v0.8:
#   - Fixed exit syntax
#   - Added visualization
# ============================================================

form Time Manipulation + Spectral Blur + Stereo Width
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Normal Speed (1.0x, no blur)
        option Slow Motion (0.75x, subtle blur)
        option Time Lapse (1.5x, no blur)
        option Ambient Stretch (2.0x, moderate blur)
        option Paulstretch-like (4.0x, heavy blur)
        option Extreme Drone (8.0x, maximum blur)
    
    comment === Time Stretch ===
    real Duration_factor 4.0
    
    comment === Spectral Blur ===
    positive Blur_amount 3
    comment (1=subtle, 3=moderate, 5=heavy, 7=extreme)
    positive Lowpass_frequency 8000
    positive Highpass_frequency 80
    
    comment === Stereo Width ===
    boolean Create_stereo_width 1
    positive Stereo_delay_ms 15
    positive Stereo_detune_amount 0.5
    
    comment === PSOLA Pitch Range ===
    positive Min_pitch 75
    positive Max_pitch 600
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Custom - use manual settings
elsif preset = 2
    # Normal Speed
    duration_factor = 1.0
    blur_amount = 0
    create_stereo_width = 0
elsif preset = 3
    # Slow Motion
    duration_factor = 0.75
    blur_amount = 1
    lowpass_frequency = 10000
elsif preset = 4
    # Time Lapse
    duration_factor = 1.5
    blur_amount = 0
    create_stereo_width = 0
elsif preset = 5
    # Ambient Stretch
    duration_factor = 2.0
    blur_amount = 3
    lowpass_frequency = 7000
    create_stereo_width = 1
elsif preset = 6
    # Paulstretch-like
    duration_factor = 4.0
    blur_amount = 5
    lowpass_frequency = 6000
    create_stereo_width = 1
elsif preset = 7
    # Extreme Drone
    duration_factor = 8.0
    blur_amount = 7
    lowpass_frequency = 5000
    highpass_frequency = 100
    create_stereo_width = 1
    stereo_delay_ms = 25
endif

# Determine if blur should be applied
if blur_amount > 0
    apply_spectral_blur = 1
else
    apply_spectral_blur = 0
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

originalSound = selected("Sound")
selectObject: originalSound
sound_name$ = selected$("Sound")

# Get original properties
duration = Get total duration
n_channels = Get number of channels
sampleRate = Get sampling frequency

# Internal guards; public form remains unchanged.
if duration_factor <= 0
    exitScript: "Duration_factor must be greater than zero."
endif
if min_pitch >= max_pitch
    exitScript: "Min_pitch must be lower than Max_pitch."
endif
safeMaxPitch = min(max_pitch, sampleRate * 0.45)
if safeMaxPitch <= min_pitch
    exitScript: "Pitch range is invalid for this sampling rate."
endif

blurPasses = floor(blur_amount)
if blurPasses < 0
    blurPasses = 0
endif
nyquistSafe = sampleRate * 0.49
effectiveLowpass = min(lowpass_frequency, nyquistSafe)
effectiveHighpass = highpass_frequency
if effectiveHighpass < 0
    effectiveHighpass = 0
endif
if apply_spectral_blur and effectiveHighpass >= effectiveLowpass
    exitScript: "Highpass_frequency must be below the effective Lowpass_frequency/Nyquist."
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Normal"
elsif preset = 3
    presetName$ = "Slow Motion"
elsif preset = 4
    presetName$ = "Time Lapse"
elsif preset = 5
    presetName$ = "Ambient"
elsif preset = 6
    presetName$ = "Paulstretch"
else
    presetName$ = "Extreme"
endif

# === Info ===
writeInfoLine: "=== Time Manipulation ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Duration factor: ", duration_factor, "x"
appendInfoLine: "Blur amount: ", blur_amount
if create_stereo_width
    appendInfoLine: "Stereo width: ", stereo_delay_ms, " ms"
endif
appendInfoLine: ""

# === Convert to Mono for Processing ===
if n_channels > 1
    appendInfoLine: "Converting to mono for processing..."
    selectObject: originalSound
    sound = Convert to mono
else
    selectObject: originalSound
    Copy: "mono_temp"
    sound = selected("Sound")
endif

# Private zero-based work domain; original is never shifted.
selectObject: sound
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# ============================================================
# STEP 1: Fast PSOLA Time-Stretching
# ============================================================
appendInfoLine: "1. PSOLA time-stretching..."

selectObject: sound
manipulation = To Manipulation: 0.01, min_pitch, safeMaxPitch

durationTier = Create DurationTier: "duration", 0, duration
Add point: 0, duration_factor
Add point: duration, duration_factor

selectObject: manipulation
plusObject: durationTier
Replace duration tier

selectObject: manipulation
resynthesized = Get resynthesis (overlap-add)

removeObject: durationTier, manipulation

selectObject: resynthesized
stretched_duration = Get total duration
appendInfoLine: "   Stretched to: ", fixed$(stretched_duration, 3), " s"

# ============================================================
# STEP 2: Spectral Blur
# ============================================================
if apply_spectral_blur
    appendInfoLine: "2. Applying spectral blur..."

    # Initial band-pass.
    selectObject: resynthesized
    Filter (pass Hann band): effectiveHighpass, 0, 100
    current_sound = selected("Sound")
    removeObject: resynthesized

    selectObject: current_sound
    Filter (pass Hann band): 0, effectiveLowpass, 100
    new_sound = selected("Sound")
    removeObject: current_sound
    current_sound = new_sound

    # Cascaded lowpass filters. Preserve the original linear trajectory,
    # but clamp at a valid floor so high Blur_amount values still add passes.
    cutoffFloor = effectiveHighpass + 100
    if cutoffFloor > effectiveLowpass
        cutoffFloor = effectiveLowpass
    endif

    for i_pass from 1 to blurPasses
        cutoff_ratio = 1.0 - (i_pass * 0.15)
        current_cutoff = effectiveLowpass * cutoff_ratio
        if current_cutoff < cutoffFloor
            current_cutoff = cutoffFloor
        endif

        selectObject: current_sound
        Filter (pass Hann band): 0, current_cutoff, 100
        new_sound = selected("Sound")
        removeObject: current_sound
        current_sound = new_sound

        appendInfoLine: "   Pass ", i_pass, ": lowpass at ", round(current_cutoff), " Hz"
    endfor

    resynthesized = current_sound
    selectObject: resynthesized
    appendInfoLine: "   Spectral blur complete"
else
    appendInfoLine: "2. Skipping spectral blur (amount = 0)"
endif

# ============================================================
# STEP 3: Create Stereo Width Effect
# ============================================================
if create_stereo_width
    appendInfoLine: "3. Creating stereo width effect..."
    
    selectObject: resynthesized
    fs = Get sampling frequency
    
    # Create LEFT channel (original with slight filtering)
    selectObject: resynthesized
    Copy: "left"
    left_channel = selected("Sound")
    
    # Slightly darker on left
    if stereo_detune_amount > 0
        left_cutoff = effectiveLowpass * (1.0 - stereo_detune_amount * 0.1)
        left_cutoff = max(effectiveHighpass + 1, min(left_cutoff, nyquistSafe))
        Filter (pass Hann band): 0, left_cutoff, 50
        left_filtered = selected("Sound")
        removeObject: left_channel
        left_channel = left_filtered
    endif
    
    # Create RIGHT channel (delayed and slightly different filtering)
    selectObject: resynthesized
    Copy: "right"
    right_channel = selected("Sound")
    
    # Slightly brighter on right
    if stereo_detune_amount > 0
        right_cutoff = effectiveLowpass * (1.0 + stereo_detune_amount * 0.05)
        right_cutoff = max(effectiveHighpass + 1, min(right_cutoff, nyquistSafe))
        if right_cutoff < fs / 2
            Filter (pass Hann band): 0, right_cutoff, 50
            right_filtered = selected("Sound")
            removeObject: right_channel
            right_channel = right_filtered
        endif
    endif
    
    # Apply delay to right channel
    delay_seconds = stereo_delay_ms / 1000

    # Concatenate follows Object-list order. Create silence FIRST and a fresh
    # right-channel body SECOND, guaranteeing silence + audio.
    silence_for_delay = Create Sound from formula: "delay_silence", 1, 0, delay_seconds, fs, "0"
    selectObject: right_channel
    right_delay_body = Copy: "right_delay_body"
    selectObject: silence_for_delay, right_delay_body
    right_delayed = Concatenate
    removeObject: silence_for_delay, right_delay_body, right_channel

    # Pad left to match duration
    selectObject: right_delayed
    right_dur = Get total duration
    selectObject: left_channel
    left_dur = Get total duration
    
    if right_dur > left_dur
        pad_needed = right_dur - left_dur
        silence_pad = Create Sound from formula: "pad", 1, 0, pad_needed, fs, "0"
        selectObject: left_channel, silence_pad
        left_padded = Concatenate
        removeObject: silence_pad, left_channel
        left_channel = left_padded
    endif
    
    # Combine to stereo. Fresh copies force Object-list order = Left, Right.
    selectObject: left_channel
    left_for_stereo = Copy: "left_for_stereo"
    selectObject: right_delayed
    right_for_stereo = Copy: "right_for_stereo"
    selectObject: left_for_stereo, right_for_stereo
    stereo_result = Combine to stereo

    removeObject: left_for_stereo, right_for_stereo, left_channel, right_delayed, resynthesized
    result = stereo_result

    appendInfoLine: "   Stereo width: ", stereo_delay_ms, " ms delay"
else
    result = resynthesized
    appendInfoLine: "3. Skipping stereo width"
endif

# ============================================================
# Finalize
# ============================================================
selectObject: result
final_duration = Get total duration
final_channels = Get number of channels
Rename: sound_name$ + "_stretched_" + string$(duration_factor) + "x"
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: 0.99
endif

# === Cleanup ===
removeObject: sound

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Time Manipulation: " + sound_name$ + " (" + presetName$ + ", " + fixed$(duration_factor, 1) + "x)"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: originalSound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    Text bottom: "yes", fixed$(duration, 2) + " s"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Stretched"
    Text bottom: "yes", fixed$(final_duration, 2) + " s"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    specMaxHz = min(5000, nyquistSafe)
    selectObject: originalSound
    if n_channels > 1
        origSpecMono = Convert to mono
    else
        origSpecMono = Copy: "origSpecMono"
    endif
    selectObject: origSpecMono
    To Spectrogram: 0.03, specMaxHz, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec, origSpecMono
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"

    # Result spectrogram
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    if final_channels > 1
        resSpecMono = Convert to mono
    else
        resSpecMono = Copy: "resSpecMono"
    endif
    selectObject: resSpecMono
    To Spectrogram: 0.03, specMaxHz, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, resSpecMono
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Stretched + Blur"

    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    statsText$ = "Factor: " + fixed$(duration_factor, 1) + "x | Blur: " + string$(blur_amount) + " | "
    if create_stereo_width
        statsText$ = statsText$ + "Stereo: " + fixed$(stereo_delay_ms, 0) + "ms"
    else
        statsText$ = statsText$ + "Mono output"
    endif
    statsText$ = statsText$ + " | " + fixed$(duration, 2) + "s → " + fixed$(final_duration, 2) + "s"
    
    Text: 0.5, "centre", 0.5, "half", statsText$
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(duration, 2), " s → ", fixed$(final_duration, 2), " s"
appendInfoLine: "Channels: ", final_channels

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result