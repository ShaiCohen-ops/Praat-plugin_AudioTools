# ============================================================
# Praat AudioTools - Virtual Subharmonic Generator
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phantom Bass Enhancer + Haas Stereo Widener
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Phantom Bass Enhancer + Haas Stereo Widener 


form Phantom Bass + Stereo Widener
    comment === PRESETS ===
    optionmenu preset 1
        option Custom (use settings below)
        option Subtle Enhancement
        option Moderate Effect
        option Aggressive MaxxBass Style
        option Mono-Safe Widening
        option Wide Stereo (not mono-safe)
    
    comment === Phantom Bass (Waveshaping Method) ===
    comment Bass analysis range (Hz):
    positive bass_low_freq 30
    positive bass_high_freq 120
    comment Drive (0.1-10): higher = more harmonics:
    positive drive 3.0
    comment Harmonic mix (0-1): 0=dry, 1=full effect:
    real harmonic_mix 0.6
    comment High-pass original at (Hz):
    positive highpass_freq 100
    comment Harmonic brightness (lowpass Hz):
    positive harmonic_lowpass 800
    
    comment === Haas Effect (use subtly!) ===
    boolean apply_haas 1
    positive haas_delay_ms 15
    real haas_mix 0.5
    real level_difference_db -3
    
    comment === Mid-Side Widening ===
    boolean apply_ms_widening 1
    real stereo_width 0.5
    
    comment === Safety ===
    boolean preserve_mono_compatibility 1
    
    comment === Playback ===
    boolean play_result 1
endform

# Apply preset parameters
if preset = 2
    # Subtle Enhancement
    drive = 2.0
    harmonic_mix = 0.4
    highpass_freq = 90
    harmonic_lowpass = 600
    apply_haas = 1
    haas_delay_ms = 10
    haas_mix = 0.3
    apply_ms_widening = 1
    stereo_width = 0.3
    preserve_mono_compatibility = 1
elsif preset = 3
    # Moderate Effect
    drive = 3.0
    harmonic_mix = 0.6
    highpass_freq = 100
    harmonic_lowpass = 800
    apply_haas = 1
    haas_delay_ms = 15
    haas_mix = 0.5
    apply_ms_widening = 1
    stereo_width = 0.5
    preserve_mono_compatibility = 1
elsif preset = 4
    # Aggressive MaxxBass Style
    drive = 5.0
    harmonic_mix = 0.8
    highpass_freq = 120
    harmonic_lowpass = 1000
    apply_haas = 1
    haas_delay_ms = 20
    haas_mix = 0.6
    apply_ms_widening = 1
    stereo_width = 0.7
    preserve_mono_compatibility = 0
elsif preset = 5
    # Mono-Safe Widening
    drive = 2.5
    harmonic_mix = 0.5
    highpass_freq = 100
    harmonic_lowpass = 700
    apply_haas = 1
    haas_delay_ms = 8
    haas_mix = 0.2
    apply_ms_widening = 1
    stereo_width = 0.4
    preserve_mono_compatibility = 1
elsif preset = 6
    # Wide Stereo (not mono-safe)
    drive = 3.5
    harmonic_mix = 0.65
    highpass_freq = 100
    harmonic_lowpass = 900
    apply_haas = 1
    haas_delay_ms = 25
    haas_mix = 0.7
    apply_ms_widening = 1
    stereo_width = 0.8
    preserve_mono_compatibility = 0
endif

# Store original
original = selected("Sound")
originalName$ = selected$("Sound")
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels

# Convert to stereo if mono
if numChannels = 1
    select original
    stereo_temp = Convert to stereo
    working_sound = stereo_temp
    was_mono = 1
else
    working_sound = original
    was_mono = 0
endif

# === STAGE 1: EXTRACT BASS CONTENT ===
select working_sound
left_channel = Extract one channel: 1
select working_sound
right_channel = Extract one channel: 2

# Process LEFT channel
select left_channel
bass_left_copy = Copy: "bass_L"
Filter (pass Hann band): bass_low_freq, bass_high_freq, 100
bass_left_filtered = selected("Sound")

# Process RIGHT channel
select right_channel
bass_right_copy = Copy: "bass_R"
Filter (pass Hann band): bass_low_freq, bass_high_freq, 100
bass_right_filtered = selected("Sound")

# Remove unfiltered copies
select bass_left_copy
plus bass_right_copy
Remove

# === STAGE 2: GENERATE HARMONICS VIA WAVESHAPING ===
# LEFT harmonics
select bass_left_filtered
harmonics_left = Copy: "harm_L"
Formula: "tanh('drive' * self)"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmonics_left_filtered = selected("Sound")
harmonics_left_name$ = selected$("Sound")
select harmonics_left
Remove

# RIGHT harmonics
select bass_right_filtered
harmonics_right = Copy: "harm_R"
Formula: "tanh('drive' * self)"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmonics_right_filtered = selected("Sound")
harmonics_right_name$ = selected$("Sound")
select harmonics_right
Remove

# === STAGE 3: HIGH-PASS ORIGINAL CHANNELS ===
select left_channel
Filter (stop Hann band): 0, highpass_freq, 100
left_highpassed = selected("Sound")

select right_channel
Filter (stop Hann band): 0, highpass_freq, 100
right_highpassed = selected("Sound")

# Remove original channel extracts
select left_channel
plus right_channel
Remove

# === STAGE 4: MIX HARMONICS WITH HIGH-PASSED SIGNAL ===
select left_highpassed
Formula: "self + Sound_'harmonics_left_name$'[col] * 'harmonic_mix'"
left_mixed = selected("Sound")
left_mixed_name$ = selected$("Sound")

select right_highpassed
Formula: "self + Sound_'harmonics_right_name$'[col] * 'harmonic_mix'"
right_mixed = selected("Sound")
right_mixed_name$ = selected$("Sound")

# Clean up bass and harmonic intermediates
select bass_left_filtered
plus bass_right_filtered
plus harmonics_left_filtered
plus harmonics_right_filtered
Remove

# === PEAK SAFETY PASS 1: After harmonic mix ===
select left_mixed
max_left = Get maximum: 0, 0, "None"
min_left = Get minimum: 0, 0, "None"
select right_mixed
max_right = Get maximum: 0, 0, "None"
min_right = Get minimum: 0, 0, "None"
max_peak = max(abs(max_left), abs(max_right), abs(min_left), abs(min_right))
if max_peak > 0.95
    scale_factor = 0.95 / max_peak
    select left_mixed
    Formula: "self * 'scale_factor'"
    select right_mixed
    Formula: "self * 'scale_factor'"
endif

# === STAGE 5: HAAS EFFECT (OPTIONAL) ===
if apply_haas = 1
    # Apply mono-safe parameters if flag is set
    if preserve_mono_compatibility = 1
        # Safe mode: cap delay and mix to minimize phase issues
        haas_delay_actual = min(haas_delay_ms, 12)
        haas_mix_actual = min(haas_mix, 0.25)
        haas_safety_mode$ = "ON (capped at 12ms, 25% mix)"
    else
        haas_delay_actual = haas_delay_ms
        haas_mix_actual = haas_mix
        haas_safety_mode$ = "OFF"
    endif
    
    haas_delay_samples = round(haas_delay_actual / 1000 * sampleRate)
    level_factor = 10^(level_difference_db / 20)
    
    # Create delayed version of right channel
    select right_mixed
    right_delayed = Copy: "right_delayed"
    Formula: "if col > 'haas_delay_samples' then self[col - 'haas_delay_samples'] * 'level_factor' else 0 fi"
    
    # Mix delayed with original
    select right_mixed
    Formula: "self * (1 - 'haas_mix_actual') + Sound_right_delayed[col] * 'haas_mix_actual'"
    
    select right_delayed
    Remove
    
    # === PEAK SAFETY PASS 2: After Haas ===
    select left_mixed
    max_left = Get maximum: 0, 0, "None"
    min_left = Get minimum: 0, 0, "None"
    select right_mixed
    max_right = Get maximum: 0, 0, "None"
    min_right = Get minimum: 0, 0, "None"
    max_peak = max(abs(max_left), abs(max_right), abs(min_left), abs(min_right))
    if max_peak > 0.95
        scale_factor = 0.95 / max_peak
        select left_mixed
        Formula: "self * 'scale_factor'"
        select right_mixed
        Formula: "self * 'scale_factor'"
    endif
else
    haas_safety_mode$ = "N/A (Haas disabled)"
endif

# === STAGE 6: MID-SIDE WIDENING (OPTIONAL) ===
if apply_ms_widening = 1
    # Calculate mid
    select left_mixed
    mid_signal = Copy: "mid"
    Formula: "(Sound_'left_mixed_name$'[col] + Sound_'right_mixed_name$'[col]) / 2"
    mid_name$ = selected$("Sound")
    
    # Calculate side
    select left_mixed
    side_signal = Copy: "side"
    Formula: "(Sound_'left_mixed_name$'[col] - Sound_'right_mixed_name$'[col]) / 2 * 'stereo_width'"
    
    # Mono compatibility check - high-pass side signal
    if preserve_mono_compatibility = 1
        # Reduce side at low frequencies to prevent phase issues
        select side_signal
        Filter (stop Hann band): 0, 200, 100
        side_filtered = selected("Sound")
        side_name$ = selected$("Sound")
        select side_signal
        Remove
    else
        side_name$ = selected$("Sound")
    endif
    
    # Reconstruct L/R
    select left_mixed
    Formula: "Sound_'mid_name$'[col] + Sound_'side_name$'[col]"
    
    select right_mixed
    Formula: "Sound_'mid_name$'[col] - Sound_'side_name$'[col]"
    
    select mid_signal
    if preserve_mono_compatibility = 1
        plus side_filtered
    else
        plus side_signal
    endif
    Remove
    
    # === PEAK SAFETY PASS 3: After M/S ===
    select left_mixed
    max_left = Get maximum: 0, 0, "None"
    min_left = Get minimum: 0, 0, "None"
    select right_mixed
    max_right = Get maximum: 0, 0, "None"
    min_right = Get minimum: 0, 0, "None"
    max_peak = max(abs(max_left), abs(max_right), abs(min_left), abs(min_right))
    if max_peak > 0.95
        scale_factor = 0.95 / max_peak
        select left_mixed
        Formula: "self * 'scale_factor'"
        select right_mixed
        Formula: "self * 'scale_factor'"
    endif
endif

# === STAGE 7: COMBINE TO STEREO ===
select left_mixed
plus right_mixed
final_stereo = Combine to stereo
Rename: "'originalName$'_phantom_haas"
Scale peak: 0.99

# === CLEANUP ===
select left_mixed
plus right_mixed
if was_mono = 1
    plus stereo_temp
endif
Remove

# === PLAYBACK ===
if play_result = 1
    select final_stereo
    Play
endif

# Print info
writeInfoLine: "Phantom Bass + Haas processing complete"
appendInfoLine: ""
if preset = 1
    appendInfoLine: "Preset: Custom"
elsif preset = 2
    appendInfoLine: "Preset: Subtle Enhancement"
elsif preset = 3
    appendInfoLine: "Preset: Moderate Effect"
elsif preset = 4
    appendInfoLine: "Preset: Aggressive MaxxBass Style"
elsif preset = 5
    appendInfoLine: "Preset: Mono-Safe Widening"
elsif preset = 6
    appendInfoLine: "Preset: Wide Stereo (not mono-safe)"
endif
appendInfoLine: ""
appendInfoLine: "Method: Waveshaping (tanh) generates real harmonics"
appendInfoLine: "Bass range analyzed: ", bass_low_freq, "-", bass_high_freq, " Hz"
appendInfoLine: "Original bass removed above: ", highpass_freq, " Hz"
appendInfoLine: "Drive: ", drive
appendInfoLine: "Harmonic mix: ", harmonic_mix
appendInfoLine: ""
appendInfoLine: "=== Haas Effect ==="
if apply_haas = 1
    appendInfoLine: "Delay: ", haas_delay_actual, " ms (requested: ", haas_delay_ms, ")"
    appendInfoLine: "Mix: ", haas_mix_actual, " (requested: ", haas_mix, ")"
    appendInfoLine: "Safety mode: ", haas_safety_mode$
else
    appendInfoLine: "Status: OFF"
endif
appendInfoLine: ""
appendInfoLine: "=== Stereo Widening ==="
if apply_ms_widening = 1
    appendInfoLine: "Width: ", stereo_width
    appendInfoLine: "Side LF rolloff: ", if preserve_mono_compatibility then "ON (200Hz HPF)" else "OFF" fi
else
    appendInfoLine: "Status: OFF"
endif
appendInfoLine: ""
appendInfoLine: "=== Mono Compatibility ==="
appendInfoLine: "Protection: ", if preserve_mono_compatibility then "ON" else "OFF" fi
if preserve_mono_compatibility = 1
    appendInfoLine: "  • Haas limited to safe values"
    appendInfoLine: "  • Side signal high-passed at 200Hz"
endif
appendInfoLine: ""
appendInfoLine: "⚠ ALWAYS TEST IN MONO to verify phase cancellation!"