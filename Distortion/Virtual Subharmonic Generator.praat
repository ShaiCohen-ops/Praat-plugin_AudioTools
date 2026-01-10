# ============================================================
# Praat AudioTools - Virtual_Subharmonic_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Virtual Subharmonic Generator - combines phantom bass
#   enhancement (MaxxBass-style harmonic generation), Haas
#   stereo widening, and Mid-Side processing. Creates
#   perceived bass on small speakers by generating upper
#   harmonics that the brain interprets as bass fundamental.
#   Includes mono-compatibility protection.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection syntax (use object IDs)
#   - Fixed formula syntax (string building)
#   - Fixed name-based references
#   - Added visualization
# ============================================================

form Virtual Subharmonic Generator
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Enhancement
        option Moderate Effect
        option Aggressive MaxxBass
        option Mono-Safe Widening
        option Wide Stereo (not mono-safe)
    
    comment === Phantom Bass ===
    positive Bass_low_freq 30
    positive Bass_high_freq 120
    positive Drive 3.0
    comment (higher = more harmonics)
    real Harmonic_mix 0.6
    comment (0=dry, 1=full harmonics)
    positive Highpass_freq 100
    positive Harmonic_lowpass 800
    
    comment === Haas Effect ===
    boolean Apply_haas 1
    positive Haas_delay_ms 15
    real Haas_mix 0.5
    real Level_difference_dB -3
    
    comment === Mid-Side Widening ===
    boolean Apply_MS_widening 1
    real Stereo_width 0.5
    
    comment === Safety ===
    boolean Preserve_mono_compatibility 1
    
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
sr = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Enhancement
    drive = 2.0
    harmonic_mix = 0.4
    highpass_freq = 90
    harmonic_lowpass = 600
    apply_haas = 1
    haas_delay_ms = 10
    haas_mix = 0.3
    apply_MS_widening = 1
    stereo_width = 0.3
    preserve_mono_compatibility = 1
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate Effect
    drive = 3.0
    harmonic_mix = 0.6
    highpass_freq = 100
    harmonic_lowpass = 800
    apply_haas = 1
    haas_delay_ms = 15
    haas_mix = 0.5
    apply_MS_widening = 1
    stereo_width = 0.5
    preserve_mono_compatibility = 1
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive MaxxBass
    drive = 5.0
    harmonic_mix = 0.8
    highpass_freq = 120
    harmonic_lowpass = 1000
    apply_haas = 1
    haas_delay_ms = 20
    haas_mix = 0.6
    apply_MS_widening = 1
    stereo_width = 0.7
    preserve_mono_compatibility = 0
    presetName$ = "Aggressive"
elsif preset = 5
    # Mono-Safe Widening
    drive = 2.5
    harmonic_mix = 0.5
    highpass_freq = 100
    harmonic_lowpass = 700
    apply_haas = 1
    haas_delay_ms = 8
    haas_mix = 0.2
    apply_MS_widening = 1
    stereo_width = 0.4
    preserve_mono_compatibility = 1
    presetName$ = "MonoSafe"
elsif preset = 6
    # Wide Stereo
    drive = 3.5
    harmonic_mix = 0.65
    highpass_freq = 100
    harmonic_lowpass = 900
    apply_haas = 1
    haas_delay_ms = 25
    haas_mix = 0.7
    apply_MS_widening = 1
    stereo_width = 0.8
    preserve_mono_compatibility = 0
    presetName$ = "WideStereo"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Virtual Subharmonic Generator ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

# Convert to stereo if mono
was_mono = 0
if numChannels = 1
    appendInfoLine: "Converting mono to stereo..."
    selectObject: original
    Convert to stereo
    workingSound = selected("Sound")
    was_mono = 1
else
    selectObject: original
    Copy: "working_temp"
    workingSound = selected("Sound")
endif

# === STAGE 1: EXTRACT BASS CONTENT ===
appendInfoLine: "Extracting bass (", bass_low_freq, "-", bass_high_freq, " Hz)..."

selectObject: workingSound
Extract one channel: 1
leftChannel = selected("Sound")

selectObject: workingSound
Extract one channel: 2
rightChannel = selected("Sound")

# Filter bass from LEFT
selectObject: leftChannel
Copy: "bass_L_temp"
bassLtemp = selected("Sound")
Filter (pass Hann band): bass_low_freq, bass_high_freq, 100
bassLfiltered = selected("Sound")
removeObject: bassLtemp

# Filter bass from RIGHT
selectObject: rightChannel
Copy: "bass_R_temp"
bassRtemp = selected("Sound")
Filter (pass Hann band): bass_low_freq, bass_high_freq, 100
bassRfiltered = selected("Sound")
removeObject: bassRtemp

# === STAGE 2: GENERATE HARMONICS VIA WAVESHAPING ===
appendInfoLine: "Generating harmonics (drive=", drive, ")..."

drive_str$ = string$(drive)

# LEFT harmonics
selectObject: bassLfiltered
Copy: "harm_L_temp"
harmLtemp = selected("Sound")
Formula: "tanh(self * " + drive_str$ + ")"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmLfiltered = selected("Sound")
removeObject: harmLtemp

# RIGHT harmonics
selectObject: bassRfiltered
Copy: "harm_R_temp"
harmRtemp = selected("Sound")
Formula: "tanh(self * " + drive_str$ + ")"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmRfiltered = selected("Sound")
removeObject: harmRtemp

# === STAGE 3: HIGH-PASS ORIGINAL CHANNELS ===
appendInfoLine: "High-passing original at ", highpass_freq, " Hz..."

selectObject: leftChannel
Filter (stop Hann band): 0, highpass_freq, 100
leftHP = selected("Sound")

selectObject: rightChannel
Filter (stop Hann band): 0, highpass_freq, 100
rightHP = selected("Sound")

removeObject: leftChannel, rightChannel

# === STAGE 4: MIX HARMONICS WITH HIGH-PASSED SIGNAL ===
appendInfoLine: "Mixing harmonics (", harmonic_mix * 100, "%)..."

mix_str$ = string$(harmonic_mix)
harmL_str$ = string$(harmLfiltered)
harmR_str$ = string$(harmRfiltered)

selectObject: leftHP
Formula: "self + object[" + harmL_str$ + "] * " + mix_str$

selectObject: rightHP
Formula: "self + object[" + harmR_str$ + "] * " + mix_str$

# Cleanup intermediates
removeObject: bassLfiltered, bassRfiltered, harmLfiltered, harmRfiltered

# Peak safety after harmonic mix
@peakSafety: leftHP, rightHP

# === STAGE 5: HAAS EFFECT (OPTIONAL) ===
if apply_haas
    appendInfoLine: "Applying Haas effect..."
    
    if preserve_mono_compatibility
        haas_delay_actual = min(haas_delay_ms, 12)
        haas_mix_actual = min(haas_mix, 0.25)
    else
        haas_delay_actual = haas_delay_ms
        haas_mix_actual = haas_mix
    endif
    
    haas_delay_samples = round(haas_delay_actual / 1000 * sr)
    level_factor = 10^(level_difference_dB / 20)
    
    delay_str$ = string$(haas_delay_samples)
    level_str$ = string$(level_factor)
    haasMix_str$ = string$(haas_mix_actual)
    oneMinusHaas_str$ = string$(1 - haas_mix_actual)
    
    # Create delayed version
    selectObject: rightHP
    Copy: "right_delayed_temp"
    rightDelayed = selected("Sound")
    Formula: "if col > " + delay_str$ + " then self[col - " + delay_str$ + "] * " + level_str$ + " else 0 fi"
    
    # Mix delayed with original
    delayed_str$ = string$(rightDelayed)
    selectObject: rightHP
    Formula: "self * " + oneMinusHaas_str$ + " + object[" + delayed_str$ + "] * " + haasMix_str$
    
    removeObject: rightDelayed
    
    # Peak safety after Haas
    @peakSafety: leftHP, rightHP
endif

# === STAGE 6: MID-SIDE WIDENING (OPTIONAL) ===
if apply_MS_widening
    appendInfoLine: "Applying M/S widening (width=", stereo_width, ")..."
    
    left_str$ = string$(leftHP)
    right_str$ = string$(rightHP)
    width_str$ = string$(stereo_width)
    
    # Calculate Mid
    selectObject: leftHP
    Copy: "mid_temp"
    midSignal = selected("Sound")
    Formula: "(object[" + left_str$ + "] + object[" + right_str$ + "]) / 2"
    
    # Calculate Side
    selectObject: leftHP
    Copy: "side_temp"
    sideSignal = selected("Sound")
    Formula: "(object[" + left_str$ + "] - object[" + right_str$ + "]) / 2 * " + width_str$
    
    # High-pass side for mono compatibility
    if preserve_mono_compatibility
        selectObject: sideSignal
        Filter (stop Hann band): 0, 200, 100
        sideFiltered = selected("Sound")
        removeObject: sideSignal
        sideSignal = sideFiltered
    endif
    
    mid_str$ = string$(midSignal)
    side_str$ = string$(sideSignal)
    
    # Reconstruct L/R
    selectObject: leftHP
    Formula: "object[" + mid_str$ + "] + object[" + side_str$ + "]"
    
    selectObject: rightHP
    Formula: "object[" + mid_str$ + "] - object[" + side_str$ + "]"
    
    removeObject: midSignal, sideSignal
    
    # Peak safety after M/S
    @peakSafety: leftHP, rightHP
endif

# === STAGE 7: COMBINE TO STEREO ===
appendInfoLine: "Combining to stereo..."

selectObject: leftHP, rightHP
Combine to stereo
result = selected("Sound")
Rename: originalName$ + "_subharm_" + presetName$

Scale peak: 0.95

# Cleanup
removeObject: leftHP, rightHP, workingSound

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Virtual Subharmonic Generator: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Enhanced"
    Text bottom: "yes", "Time (s)"
    
    # Processing chain diagram
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    Axes: 0, 10, 0, 4
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 4
    
    Font size: 5
    
    # Input
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.2, 1.0, 1.5, 2.5
    Colour: "Black"
    Text: 0.6, "centre", 2.0, "half", "Input"
    
    # Split
    Draw arrow: 1.0, 2.0, 1.5, 2.8
    Draw arrow: 1.0, 2.0, 1.5, 1.2
    
    # Bass path (top)
    Paint rectangle: "{0.7, 0.8, 0.6}", 1.5, 2.5, 2.5, 3.2
    Text: 2.0, "centre", 2.85, "half", "Bass"
    Text: 2.0, "centre", 2.6, "half", fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0)
    
    Draw arrow: 2.5, 2.85, 3.0, 2.85
    
    Paint rectangle: "{0.8, 0.7, 0.6}", 3.0, 4.0, 2.5, 3.2
    Text: 3.5, "centre", 2.85, "half", "tanh(×" + fixed$(drive, 0) + ")"
    
    Draw arrow: 4.0, 2.85, 4.5, 2.85
    
    Paint rectangle: "{0.7, 0.7, 0.8}", 4.5, 5.5, 2.5, 3.2
    Text: 5.0, "centre", 2.85, "half", "Harmonics"
    
    # Original path (bottom)
    Paint rectangle: "{0.6, 0.7, 0.7}", 1.5, 2.5, 0.8, 1.5
    Text: 2.0, "centre", 1.15, "half", "Highpass"
    Text: 2.0, "centre", 0.9, "half", fixed$(highpass_freq, 0) + " Hz"
    
    # Mix
    Draw arrow: 5.5, 2.85, 6.0, 2.2
    Draw arrow: 2.5, 1.15, 6.0, 1.8
    
    Paint rectangle: "{0.6, 0.8, 0.6}", 6.0, 6.8, 1.5, 2.5
    Text: 6.4, "centre", 2.0, "half", "Mix"
    
    # Haas
    if apply_haas
        Draw arrow: 6.8, 2.0, 7.3, 2.0
        Paint rectangle: "{0.8, 0.6, 0.6}", 7.3, 8.1, 1.5, 2.5
        Text: 7.7, "centre", 2.0, "half", "Haas"
        Draw arrow: 8.1, 2.0, 8.4, 2.0
    else
        Draw arrow: 6.8, 2.0, 8.4, 2.0
    endif
    
    # M/S
    if apply_MS_widening
        Paint rectangle: "{0.6, 0.6, 0.8}", 8.4, 9.2, 1.5, 2.5
        Text: 8.8, "centre", 2.0, "half", "M/S"
        Draw arrow: 9.2, 2.0, 9.5, 2.0
    endif
    
    # Output
    Paint rectangle: "{0.6, 0.8, 0.6}", 9.5, 9.9, 1.5, 2.5
    Text: 9.7, "centre", 2.0, "half", "Out"
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.6
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    param$ = "Drive: " + fixed$(drive, 1) + " | Mix: " + fixed$(harmonic_mix, 1)
    if apply_haas
        if preserve_mono_compatibility
            param$ = param$ + " | Haas: " + fixed$(haas_delay_actual, 0) + "ms (safe)"
        else
            param$ = param$ + " | Haas: " + fixed$(haas_delay_ms, 0) + "ms"
        endif
    endif
    if apply_MS_widening
        param$ = param$ + " | Width: " + fixed$(stereo_width, 1)
    endif
    if preserve_mono_compatibility
        param$ = param$ + " | Mono-safe: ON"
    endif
    
    Text: 0.5, "centre", 0.5, "half", param$
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Processing Complete ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: ""
appendInfoLine: "Phantom Bass: drive=", drive, ", mix=", harmonic_mix
if apply_haas
    appendInfoLine: "Haas: ", haas_delay_actual, "ms delay, ", haas_mix_actual, " mix"
endif
if apply_MS_widening
    appendInfoLine: "M/S Width: ", stereo_width
endif
appendInfoLine: "Mono compatibility: ", if preserve_mono_compatibility then "ON" else "OFF" fi

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

procedure peakSafety: .left, .right
    selectObject: .left
    .maxL = Get maximum: 0, 0, "None"
    .minL = Get minimum: 0, 0, "None"
    selectObject: .right
    .maxR = Get maximum: 0, 0, "None"
    .minR = Get minimum: 0, 0, "None"
    
    .maxPeak = max(abs(.maxL), abs(.maxR), abs(.minL), abs(.minR))
    
    if .maxPeak > 0.95
        .scale = 0.95 / .maxPeak
        .scale$ = string$(.scale)
        selectObject: .left
        Formula: "self * " + .scale$
        selectObject: .right
        Formula: "self * " + .scale$
    endif
endproc