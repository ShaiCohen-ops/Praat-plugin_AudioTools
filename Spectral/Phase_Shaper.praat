# ============================================================
# Praat AudioTools - Phase Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.5 (2026)
# License: MIT License
#
# Description:
#   Convolution-based sound design using custom impulse responses.
#   The historical name "Phase Shaper" is creative rather than literal: the
#   processor does not directly edit spectral phase. It builds an IR (chirps,
#   noise, resonators, glitches) and convolves that IR with the source, so both
#   magnitude and phase follow the IR transfer function. Effects include
#   dispersion, freeze-like smearing, rhythmic tails, resonances and glitches.
#
# Changelog v0.5:
#   - FIX: native stereo is no longer collapsed to mono when Stereo_output is on.
#     Praat can convolve a multichannel Sound directly with a mono IR, so L/R
#     relationships (including anti-phase material) are now preserved.
#   - FIX: wet/dry mixing is row-aware for multichannel material.
#   - CLARITY: Stereo_output now means preserve native stereo, or create the
#     existing 15-ms pseudo-stereo delay when the input is mono.
#   - ROBUSTNESS: Scale_peak is validated to (0,1]; flagged random/noise IRs
#     have their measured DC removed whenever non-zero, not only above 0.001.
#   - VIZ: existing process view retained; input/output use one amplitude scale
#     and the IR spectrum plot never extends above Nyquist.
#
# Changelog v0.4:
#   - Fixed pseudo-stereo branch (invalid Get/object[] args -> crash on
#     mono input, which was the default)
#   - Visualization now draws the ACTUAL IR used (kept alive, not a
#     regenerated copy) - removes ~100 lines of duplicated, drifted code
#   v0.3:
#   - Fixed chirp formula; wet/dry; presets; IR viz; stereo; trim; DC removal
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Phase Shaper v0.5
    comment === Select Mode ===
    optionmenu Mode: 1
        option Hyper-Dispersion (sweeping drone)
        option Quantum Rain (rhythmic smear)
        option Fractal Zap (FM texture)
        option Reverse Black Hole (sucking)
        option Alien Resonator (metallic chord)
        option Cyber Glitch (8-bit data)
        option Bouncing Ball (acceleration)
        option Deep Space (low rumble)
        option Spectral Freeze (infinite pad)
        option Demon Growl (AM texture)
        option Shattered Glass (bright chaos)
        option Tape Deterioration (warped)
    comment === Preset (overrides intensity) ===
    optionmenu Preset: 1
        option Custom (use intensity below)
        option Subtle
        option Medium
        option Heavy
        option Extreme
    comment === Parameters ===
    positive Intensity: 1.0
    comment (controls length, density, or aggression)
    real Wet_dry_percent: 100
    comment (0 = dry, 100 = full wet)
    comment === Output Options ===
    boolean Trim_to_original: 0
    boolean Stereo_output: 1
    positive Scale_peak: 0.95
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")
selectObject: original
original_sr = Get sampling frequency
original_dur = Get total duration
num_channels = Get number of channels

if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and at most 1."
endif

# === APPLY PRESET ===
if preset = 2
    # Subtle
    intensity = 0.5
    wet_dry_percent = 50
elsif preset = 3
    # Medium
    intensity = 1.0
    wet_dry_percent = 75
elsif preset = 4
    # Heavy
    intensity = 1.5
    wet_dry_percent = 90
elsif preset = 5
    # Extreme
    intensity = 2.5
    wet_dry_percent = 100
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Get preset name for labeling
if preset = 1
    preset_name$ = "custom"
elsif preset = 2
    preset_name$ = "subtle"
elsif preset = 3
    preset_name$ = "medium"
elsif preset = 4
    preset_name$ = "heavy"
else
    preset_name$ = "extreme"
endif

# Mode names for labeling
if mode = 1
    mode_name$ = "Hyper-Dispersion"
    suffix$ = "_hyper"
elsif mode = 2
    mode_name$ = "Quantum Rain"
    suffix$ = "_rain"
elsif mode = 3
    mode_name$ = "Fractal Zap"
    suffix$ = "_fractal"
elsif mode = 4
    mode_name$ = "Reverse Black Hole"
    suffix$ = "_blackhole"
elsif mode = 5
    mode_name$ = "Alien Resonator"
    suffix$ = "_resonator"
elsif mode = 6
    mode_name$ = "Cyber Glitch"
    suffix$ = "_glitch"
elsif mode = 7
    mode_name$ = "Bouncing Ball"
    suffix$ = "_bounce"
elsif mode = 8
    mode_name$ = "Deep Space"
    suffix$ = "_space"
elsif mode = 9
    mode_name$ = "Spectral Freeze"
    suffix$ = "_freeze"
elsif mode = 10
    mode_name$ = "Demon Growl"
    suffix$ = "_demon"
elsif mode = 11
    mode_name$ = "Shattered Glass"
    suffix$ = "_shatter"
else
    mode_name$ = "Tape Deterioration"
    suffix$ = "_tape"
endif

# Prepare wet and dry paths.
# With Stereo_output enabled, preserve native multichannel relationships:
# Praat convolves every channel of a multichannel source with the same mono IR.
# If Stereo_output is disabled, explicitly collapse the source to mono.
if num_channels > 1 and stereo_output
    selectObject: original
    sound = Copy: "working"
    selectObject: original
    dry_sound = Copy: "dry"
    appendStereoMode$ = "native channels preserved"
elsif num_channels > 1
    selectObject: original
    sound = Convert to mono
    selectObject: original
    dry_sound = Convert to mono
    appendStereoMode$ = "mono output requested"
else
    selectObject: original
    sound = Copy: "working"
    selectObject: original
    dry_sound = Copy: "dry"
    if stereo_output
        appendStereoMode$ = "mono -> 15 ms pseudo-stereo"
    else
        appendStereoMode$ = "mono"
    endif
endif

writeInfoLine: "=== Phase Shaper v0.5 ==="
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Intensity: ", fixed$(intensity, 2)
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Channel mode: ", appendStereoMode$
appendInfoLine: ""

# === GENERATE IMPULSE RESPONSE ===
nyquist = original_sr / 2
needs_dc_removal = 0

if mode = 1
    # HYPER DISPERSION - sweeping chirp (FIXED formula)
    ir_dur = 3.0 * intensity
    f0 = 50
    f1 = nyquist * 0.8
    # Proper linear chirp: phase = 2*pi * (f0*t + (f1-f0)/(2*T) * t^2)
    f0_str$ = string$(f0)
    sweep_rate$ = string$((f1 - f0) / (2 * ir_dur))
    dur_str$ = string$(ir_dur)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "0.5 * sin(2*pi * (" + f0_str$ + "*x + " + sweep_rate$ + "*x^2))"
    Formula: "self * (1 - x/" + dur_str$ + ")"

elsif mode = 2
    # QUANTUM RAIN - gated noise bursts
    ir_dur = 2.0 * intensity
    gate_freq = 15 * intensity
    gate_str$ = string$(gate_freq)
    dur_str$ = string$(ir_dur)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.5)"
    Formula: "self * (if sin(2*pi * " + gate_str$ + " * x) > 0.7 then 1 else 0 fi) * exp(-2*x/" + dur_str$ + ")"
    needs_dc_removal = 1

elsif mode = 3
    # FRACTAL ZAP - FM synthesis texture
    ir_dur = 0.5 * intensity
    mod_freq = 500 * intensity
    mod_str$ = string$(mod_freq)
    dur_str$ = string$(ir_dur)
    # Carrier with increasing frequency, modulated by sine
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "sin(2*pi * (20 + 2000*x/" + dur_str$ + ") * x + 5*sin(2*pi*" + mod_str$ + "*x))"
    Formula: "self * (1 - x/" + dur_str$ + ")^2"

elsif mode = 4
    # REVERSE BLACK HOLE - exponential swell
    ir_dur = 1.5 * intensity
    dur_str$ = string$(ir_dur)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.3)"
    # Exponential rise toward end
    Formula: "self * exp(6 * (x/" + dur_str$ + " - 1))"
    needs_dc_removal = 1

elsif mode = 5
    # ALIEN RESONATOR - inharmonic chord
    ir_dur = 1.5 * intensity
    fb = 400 * intensity
    f1$ = string$(fb)
    f2$ = string$(fb * 1.414)
    f3$ = string$(fb * 2.236)
    f4$ = string$(fb * 3.162)
    dur_str$ = string$(ir_dur)
    # Inharmonic partials (sqrt ratios for bell-like quality)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "(sin(2*pi*" + f1$ + "*x) + 0.7*sin(2*pi*" + f2$ + "*x) + 0.5*sin(2*pi*" + f3$ + "*x) + 0.3*sin(2*pi*" + f4$ + "*x)) * exp(-4*x/" + dur_str$ + ")"

elsif mode = 6
    # CYBER GLITCH - quantized chirp
    ir_dur = 0.4 * intensity
    dur_str$ = string$(ir_dur)
    chirp_rate = 100 * intensity
    rate_str$ = string$(chirp_rate)
    # Square wave via sign function of sine chirp
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "if sin(2*pi * (200*x + " + rate_str$ + "*x^2)) > 0 then 0.8 else -0.8 fi"
    Formula: "self * (1 - x/" + dur_str$ + ")"

elsif mode = 7
    # BOUNCING BALL - accelerating impulses
    ir_dur = 1.2 * intensity
    dur_str$ = string$(ir_dur)
    accel = 150 * intensity
    accel_str$ = string$(accel)
    # Cubic phase for acceleration effect
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "sin(2*pi * " + accel_str$ + " * x^3)"
    # Threshold to create impulses
    Formula: "if abs(self) > 0.95 then self else 0 fi"
    Formula: "self * (1 - x/" + dur_str$ + ")"

elsif mode = 8
    # DEEP SPACE - low filtered noise
    ir_dur = 4.0 * intensity
    dur_str$ = string$(ir_dur)
    cutoff = 150 / intensity
    if cutoff < 50
        cutoff = 50
    endif
    Create Sound from formula: "IR_noise", 1, 0, ir_dur, original_sr, "randomGauss(0, 1)"
    noise_id = selected("Sound")
    filtered_id = Filter (pass Hann band): 0, cutoff, cutoff * 0.5
    removeObject: noise_id
    selectObject: filtered_id
    Rename: "IR"
    Formula: "self * (1 - (x/" + dur_str$ + ")^0.5)"
    needs_dc_removal = 1

elsif mode = 9
    # SPECTRAL FREEZE - long noise smear
    ir_dur = 6.0 * intensity
    dur_str$ = string$(ir_dur)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.15)"
    # Very slow decay for pad-like sustain
    Formula: "self * exp(-0.5 * x/" + dur_str$ + ")"
    needs_dc_removal = 1

elsif mode = 10
    # DEMON GROWL - AM modulated noise with sub-harmonics
    ir_dur = 1.2 * intensity
    dur_str$ = string$(ir_dur)
    am_rate = 25 * intensity
    am_str$ = string$(am_rate)
    sub_str$ = string$(am_rate / 3)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "randomGauss(0, 0.5) * (0.5 + 0.5*sin(2*pi*" + am_str$ + "*x)) * (0.7 + 0.3*sin(2*pi*" + sub_str$ + "*x))"
    Formula: "self * exp(-2*x/" + dur_str$ + ")"
    needs_dc_removal = 1

elsif mode = 11
    # SHATTERED GLASS - bright chaotic bursts
    ir_dur = 0.25 * intensity
    dur_str$ = string$(ir_dur)
    # High frequency noise with rapid decay
    hf = min(12000, nyquist * 0.9)
    hf_str$ = string$(hf)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "randomGauss(0, 0.9) * sin(2*pi * " + hf_str$ + " * x * (1 + 0.5*randomGauss(0,1)))"
    Formula: "self * exp(-15*x/" + dur_str$ + ")"
    needs_dc_removal = 1

elsif mode = 12
    # TAPE DETERIORATION - warped flutter with wow
    ir_dur = 2.0 * intensity
    dur_str$ = string$(ir_dur)
    wow_rate = 3 + 2 * intensity
    flutter_rate = 8 * intensity
    wow_str$ = string$(wow_rate)
    flutter_str$ = string$(flutter_rate)
    # Frequency modulated by both slow wow and faster flutter
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, 
        ... "sin(2*pi * (180 + 40*sin(2*pi*" + wow_str$ + "*x) + 15*sin(2*pi*" + flutter_str$ + "*x)) * x) * exp(-2*x/" + dur_str$ + ")"
endif

ir_id = selected("Sound")

# === DC REMOVAL for noise-based modes ===
if needs_dc_removal
    selectObject: ir_id
    dc_mean = Get mean: 0, 0
    if abs(dc_mean) > 1e-15
        Formula: "self - " + string$(dc_mean)
    endif
endif

# Normalize IR
selectObject: ir_id
Scale peak: 0.99

appendInfoLine: "IR duration: ", fixed$(ir_dur, 3), " s"
appendInfoLine: "IR samples: ", round(ir_dur * original_sr)

# === CONVOLUTION ===
appendInfoLine: ""
appendInfoLine: "Convolving..."

selectObject: sound
plusObject: ir_id
convolved = Convolve: "sum", "zero"

# Get convolved duration before any trimming
selectObject: convolved
conv_dur = Get total duration

# === TRIM TO ORIGINAL if requested ===
if trim_to_original
    selectObject: convolved
    trimmed = Extract part: 0, original_dur, "rectangular", 1, "no"
    removeObject: convolved
    convolved = trimmed
    appendInfoLine: "Trimmed to original duration: ", fixed$(original_dur, 3), " s"
endif

# === WET/DRY MIX ===
if dry_level > 0
    selectObject: convolved
    current_dur = Get total duration
    
    # Extend dry sound if convolved is longer, preserving all dry channels.
    selectObject: dry_sound
    dry_dur = Get total duration
    dry_channels_for_pad = Get number of channels
    dry_samples = Get number of samples
    dry_id_for_pad$ = string$(dry_sound)

    if current_dur > dry_dur and not trim_to_original
        Create Sound from formula: "dry_extended", dry_channels_for_pad, 0, current_dur, original_sr,
            ... "if col <= " + string$(dry_samples) + " then object[" + dry_id_for_pad$ + ", row, col] else 0 fi"
        extended_dry = selected("Sound")
        removeObject: dry_sound
        dry_sound = extended_dry
    endif

    # Mix: result = wet * convolved + dry * original
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: convolved
    wet_channels = Get number of channels
    selectObject: dry_sound
    dry_channels = Get number of channels
    selectObject: convolved
    if wet_channels = dry_channels
        Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$
    else
        # Defensive fallback; normal routing above keeps channel counts matched.
        Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", 1, col] * " + dry_str$
    endif
endif

# === STEREO OUTPUT ===
# Native stereo/multichannel input has already remained multichannel through
# convolution and wet/dry mixing. Only mono input needs synthetic stereo.
if stereo_output and num_channels = 1
    # Create pseudo-stereo: left = exact wet/dry result, right = same delayed slightly.
    selectObject: convolved
    ps_dur = Get total duration
    delay_samples = round(0.015 * original_sr)
    delay_str$ = string$(delay_samples)
    mono_id_str$ = string$(convolved)

    # left channel = exact copy
    selectObject: convolved
    left_ch = Copy: "left"

    # right channel = copy, shifted later by delay_samples (reads from the
    # source by sample index; zero before the delay)
    Create Sound from formula: "right", 1, 0, ps_dur, original_sr,
        ... "if col > " + delay_str$ + " then object[" + mono_id_str$ +
        ... ", col - " + delay_str$ + "] else 0 fi"
    right_ch = selected("Sound")

    selectObject: left_ch
    plusObject: right_ch
    stereo_result = Combine to stereo
    removeObject: left_ch, right_ch, convolved
    convolved = stereo_result
endif

# === FINALIZE ===
selectObject: convolved
Scale peak: scale_peak
Rename: original_name$ + suffix$ + "_" + preset_name$

result = convolved

# Cleanup (keep ir_id alive for the visualization; removed at the very end)
removeObject: sound, dry_sound

# === VISUALIZATION ===
if draw_visualization
    # Draw the ACTUAL impulse response used (no regeneration, no drift).
    selectObject: ir_id
    ir_viz = Copy: "IR_viz"
    Scale peak: 0.99
    ir_dur_viz = ir_dur

    # Create spectrum of the IR
    selectObject: ir_viz
    ir_spectrum = To Spectrum: "yes"
    
    # === DRAW ===
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phase Shaper: " + mode_name$ + " (" + preset_name$ + ")"
    
    # Input/output waveform comparison uses one amplitude scale.
    selectObject: original
    input_peak_viz = Get absolute extremum: 0, 0, "None"
    selectObject: result
    output_peak_viz = Get absolute extremum: 0, 0, "None"
    wave_peak_viz = 1.05 * max(input_peak_viz, output_peak_viz)
    if wave_peak_viz < 1e-12
        wave_peak_viz = 1
    endif

    # --- Original waveform ---
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.5, 7.5, 0.7, 1.5
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, -wave_peak_viz, wave_peak_viz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Input"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    
    # --- IR waveform ---
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.5, 7.5, 1.8, 2.6
    selectObject: ir_viz
    Colour: "{0.2, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "IR"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    
    # --- IR spectrum ---
    Select outer viewport: 0, 8, 2.8, 3.8
    Select inner viewport: 0.5, 7.5, 2.9, 3.7
    ir_plot_max = min(8000, nyquist)
    selectObject: ir_spectrum
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, ir_plot_max, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "IR Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    Marks bottom every: 1, 1000, "yes", "yes", "no"
    
    # --- Result waveform ---
    Select outer viewport: 0, 8, 3.9, 4.9
    Select inner viewport: 0.5, 7.5, 4.0, 4.8
    selectObject: result
    Colour: "{0.3, 0.7, 0.4}"
    Draw: 0, 0, -wave_peak_viz, wave_peak_viz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    
    # --- Parameters box ---
    Select outer viewport: 0, 8, 5.0, 5.5
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Intensity: " + fixed$(intensity, 2) + 
        ... " | Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%" +
        ... " | IR dur: " + fixed$(ir_dur, 2) + "s" +
        ... " | Trim: " + if trim_to_original then "yes" else "no" fi +
        ... " | Channels: " + appendStereoMode$
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup visualization objects
    removeObject: ir_viz, ir_spectrum
endif

# IR no longer needed (was kept alive for the visualization)
removeObject: ir_id

# === FINAL INFO ===
selectObject: result
result_dur = Get total duration
result_ch = Get number of channels

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(result_dur, 3), " s"
appendInfoLine: "Channels: ", result_ch
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Channel mode: ", appendStereoMode$

# === PLAY ===
if play_result
    selectObject: result
    Play
endif

selectObject: result