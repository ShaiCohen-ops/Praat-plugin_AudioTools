# ============================================================
# Praat AudioTools - Phase Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025)
# License: MIT License
#
# Description:
#   Convolution-based sound design using custom impulse responses.
#   Generates various IRs (chirps, noise, resonators, glitches)
#   and convolves them with the input to create extreme textures.
#   Effects include dispersion, freeze, rhythmic smearing, and more.
#
# Changelog v0.3:
#   - Fixed chirp formula (proper phase integration)
#   - Added wet/dry mix control
#   - Added preset system
#   - Added visualization of IR waveform and spectrum
#   - Added stereo output option
#   - Added trim-to-original option
#   - Added DC removal for noise-based modes
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Phase Shaper
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

# Handle stereo - keep copy for dry signal
if num_channels > 1
    selectObject: original
    sound = Convert to mono
    selectObject: original
    dry_sound = Convert to mono
else
    selectObject: original
    sound = Copy: "working"
    selectObject: original
    dry_sound = Copy: "dry"
endif

writeInfoLine: "=== Phase Shaper v0.3 ==="
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Intensity: ", fixed$(intensity, 2)
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
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
    if abs(dc_mean) > 0.001
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
    
    # Extend dry sound if convolved is longer
    selectObject: dry_sound
    dry_dur = Get total duration
    
    if current_dur > dry_dur and not trim_to_original
        # Pad dry sound with silence
        silence_dur = current_dur - dry_dur
        Create Sound from formula: "silence", 1, 0, silence_dur, original_sr, "0"
        silence_id = selected("Sound")
        selectObject: dry_sound
        plusObject: silence_id
        extended_dry = Concatenate
        removeObject: dry_sound, silence_id
        dry_sound = extended_dry
    endif
    
    # Mix: result = wet * convolved + dry * original
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: convolved
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# === STEREO OUTPUT ===
if stereo_output and num_channels > 1
    selectObject: convolved
    mono_result = convolved
    convolved = Convert to stereo
    removeObject: mono_result
elsif stereo_output and num_channels = 1
    # Create pseudo-stereo with slight delay
    selectObject: convolved
    mono_result = Copy: "mono_temp"
    delay_samples = round(0.015 * original_sr)
    delay_str$ = string$(delay_samples)
    
    Create Sound from formula: "left", 1, 0, Get total duration, original_sr, "object[" + string$(mono_result) + "]"
    left_ch = selected("Sound")
    
    Create Sound from formula: "right", 1, 0, object[mono_result].xmax, original_sr, 
        ... "if col > " + delay_str$ + " then object[" + string$(mono_result) + ", col - " + delay_str$ + "] else 0 fi"
    right_ch = selected("Sound")
    
    selectObject: left_ch
    plusObject: right_ch
    convolved = Combine to stereo
    
    removeObject: mono_result, left_ch, right_ch
endif

# === FINALIZE ===
selectObject: convolved
Scale peak: scale_peak
Rename: original_name$ + suffix$ + "_" + preset_name$

result = convolved

# Cleanup
removeObject: ir_id, sound, dry_sound

# === VISUALIZATION ===
if draw_visualization
    # Create fresh IR for visualization (since we removed it)
    # Regenerate IR briefly for display
    
    # --- Regenerate IR for visualization ---
    if mode = 1
        ir_dur_viz = 3.0 * intensity
        f0 = 50
        f1 = nyquist * 0.8
        f0_str$ = string$(f0)
        sweep_rate$ = string$((f1 - f0) / (2 * ir_dur_viz))
        dur_str$ = string$(ir_dur_viz)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "0.5 * sin(2*pi * (" + f0_str$ + "*x + " + sweep_rate$ + "*x^2))"
        Formula: "self * (1 - x/" + dur_str$ + ")"
    elsif mode = 2
        ir_dur_viz = 2.0 * intensity
        gate_freq = 15 * intensity
        gate_str$ = string$(gate_freq)
        dur_str$ = string$(ir_dur_viz)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, "randomGauss(0, 0.5)"
        Formula: "self * (if sin(2*pi * " + gate_str$ + " * x) > 0.7 then 1 else 0 fi) * exp(-2*x/" + dur_str$ + ")"
    elsif mode = 3
        ir_dur_viz = 0.5 * intensity
        mod_freq = 500 * intensity
        mod_str$ = string$(mod_freq)
        dur_str$ = string$(ir_dur_viz)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "sin(2*pi * (20 + 2000*x/" + dur_str$ + ") * x + 5*sin(2*pi*" + mod_str$ + "*x))"
        Formula: "self * (1 - x/" + dur_str$ + ")^2"
    elsif mode = 4
        ir_dur_viz = 1.5 * intensity
        dur_str$ = string$(ir_dur_viz)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, "randomGauss(0, 0.3)"
        Formula: "self * exp(6 * (x/" + dur_str$ + " - 1))"
    elsif mode = 5
        ir_dur_viz = 1.5 * intensity
        fb = 400 * intensity
        f1$ = string$(fb)
        f2$ = string$(fb * 1.414)
        f3$ = string$(fb * 2.236)
        f4$ = string$(fb * 3.162)
        dur_str$ = string$(ir_dur_viz)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "(sin(2*pi*" + f1$ + "*x) + 0.7*sin(2*pi*" + f2$ + "*x) + 0.5*sin(2*pi*" + f3$ + "*x) + 0.3*sin(2*pi*" + f4$ + "*x)) * exp(-4*x/" + dur_str$ + ")"
    elsif mode = 6
        ir_dur_viz = 0.4 * intensity
        dur_str$ = string$(ir_dur_viz)
        chirp_rate = 100 * intensity
        rate_str$ = string$(chirp_rate)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "if sin(2*pi * (200*x + " + rate_str$ + "*x^2)) > 0 then 0.8 else -0.8 fi"
        Formula: "self * (1 - x/" + dur_str$ + ")"
    elsif mode = 7
        ir_dur_viz = 1.2 * intensity
        dur_str$ = string$(ir_dur_viz)
        accel = 150 * intensity
        accel_str$ = string$(accel)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "sin(2*pi * " + accel_str$ + " * x^3)"
        Formula: "if abs(self) > 0.95 then self else 0 fi"
        Formula: "self * (1 - x/" + dur_str$ + ")"
    elsif mode = 8
        ir_dur_viz = 4.0 * intensity
        dur_str$ = string$(ir_dur_viz)
        cutoff = 150 / intensity
        if cutoff < 50
            cutoff = 50
        endif
        Create Sound from formula: "IR_noise_viz", 1, 0, ir_dur_viz, original_sr, "randomGauss(0, 1)"
        noise_id_viz = selected("Sound")
        ir_viz_temp = Filter (pass Hann band): 0, cutoff, cutoff * 0.5
        removeObject: noise_id_viz
        selectObject: ir_viz_temp
        Rename: "IR_viz"
        Formula: "self * (1 - (x/" + dur_str$ + ")^0.5)"
    elsif mode = 9
        ir_dur_viz = 6.0 * intensity
        dur_str$ = string$(ir_dur_viz)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, "randomGauss(0, 0.15)"
        Formula: "self * exp(-0.5 * x/" + dur_str$ + ")"
    elsif mode = 10
        ir_dur_viz = 1.2 * intensity
        dur_str$ = string$(ir_dur_viz)
        am_rate = 25 * intensity
        am_str$ = string$(am_rate)
        sub_str$ = string$(am_rate / 3)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "randomGauss(0, 0.5) * (0.5 + 0.5*sin(2*pi*" + am_str$ + "*x)) * (0.7 + 0.3*sin(2*pi*" + sub_str$ + "*x))"
        Formula: "self * exp(-2*x/" + dur_str$ + ")"
    elsif mode = 11
        ir_dur_viz = 0.25 * intensity
        dur_str$ = string$(ir_dur_viz)
        hf = min(12000, nyquist * 0.9)
        hf_str$ = string$(hf)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "randomGauss(0, 0.9) * sin(2*pi * " + hf_str$ + " * x * (1 + 0.2*randomUniform(-1,1)))"
        Formula: "self * exp(-15*x/" + dur_str$ + ")"
    else
        ir_dur_viz = 2.0 * intensity
        dur_str$ = string$(ir_dur_viz)
        wow_rate = 3 + 2 * intensity
        flutter_rate = 8 * intensity
        wow_str$ = string$(wow_rate)
        flutter_str$ = string$(flutter_rate)
        Create Sound from formula: "IR_viz", 1, 0, ir_dur_viz, original_sr, 
            ... "sin(2*pi * (180 + 40*sin(2*pi*" + wow_str$ + "*x) + 15*sin(2*pi*" + flutter_str$ + "*x)) * x) * exp(-2*x/" + dur_str$ + ")"
    endif
    
    ir_viz = selected("Sound")
    selectObject: ir_viz
    Scale peak: 0.99
    
    # Create spectrum of IR
    selectObject: ir_viz
    ir_spectrum = To Spectrum: "yes"
    
    # === DRAW ===
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phase Shaper: " + mode_name$ + " (" + preset_name$ + ")"
    
    # --- Original waveform ---
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.5, 7.5, 0.7, 1.5
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
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
    selectObject: ir_spectrum
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, 8000, 0, 0, "no"
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
    Draw: 0, 0, 0, 0, "no", "Curve"
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
        ... " | Stereo: " + if stereo_output then "yes" else "no" fi
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup visualization objects
    removeObject: ir_viz, ir_spectrum
endif

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

# === PLAY ===
if play_result
    selectObject: result
    Play
endif

selectObject: result