# ============================================================
# Praat AudioTools - Unified_Multi_Mode_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified Multi-Mode Vibrato - comprehensive vibrato toolkit
#   offering 7 different algorithms: Standard, Chirped, Rate-Mod,
#   Swarm (chorus), Enveloped, Rotary (Leslie), and Tape (Wow/Flutter).
#   Includes 14 presets from classic vocal to vintage tape effects.
#
# Changelog v2.1:
#   - Fixed input check
#   - Fixed object references (use IDs)
#   - Fixed formula syntax
#   - Removed rename hack
#   - Added visualization
#   - Added info output
# ============================================================

form Unified Multi-Mode Vibrato
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (select mode below)
        option Classic Vocal Vibrato
        option Subtle Warmth
        option Leslie Speaker (Fast)
        option Leslie Speaker (Slow)
        option Ghostly Chirp (Accelerating)
        option Drunk Tape (Wobbly Speed)
        option Insect Swarm (Chorus)
        option Fade-In Vibrato
        option Vintage Cassette (Wow & Flutter)
        option Old Reel-to-Reel (Slow Wow)
        option Damaged Tape (Heavy)
        option Warped Vinyl (Slow)
        option VHS Tracking (Fast Flutter)
    
    comment === Custom Mode (if preset is Custom) ===
    optionmenu Manual_Mode 1
        option Standard
        option Chirped
        option Rate Mod
        option Swarm
        option Enveloped
        option Rotary
        option Tape (Wow & Flutter)
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# ============================================================
# INITIALIZE DEFAULTS
# ============================================================

base_delay_ms = 5.0
modulation_depth = 0.10
base_rate_hz = 5.0
sweep_rate_hz_per_sec = 2.0
rate_sensitivity = 3.0
rate_mod_freq_hz = 0.8
number_of_layers = 6
layer_spread_hz = 0.5
attack_time_sec = 0.5
release_time_sec = 0.5
rotary_AM_Depth = 0.4
wow_Rate_Hz = 0.5
wow_Depth = 0.15
flutter_Rate_Hz = 6.0
flutter_Depth = 0.05

# ============================================================
# PRESET LOGIC
# ============================================================

if preset = 1
    # Custom Mode - use popup forms
    mode = manual_Mode
    
    if mode = 1
        beginPause: "Standard Vibrato Settings"
            positive: "base_delay_ms", 5.0
            positive: "modulation_depth", 0.10
            positive: "base_rate_hz", 5.0
        endPause: "Run", 1
        presetName$ = "Standard"
    elsif mode = 2
        beginPause: "Chirped Vibrato Settings"
            positive: "base_delay_ms", 5.0
            positive: "modulation_depth", 0.12
            positive: "base_rate_hz", 2.0
            positive: "sweep_rate_hz_per_sec", 2.0
        endPause: "Run", 1
        presetName$ = "Chirped"
    elsif mode = 3
        beginPause: "Rate Modulation Settings"
            positive: "base_delay_ms", 10.0
            positive: "modulation_depth", 0.15
            positive: "base_rate_hz", 0.5
            positive: "rate_sensitivity", 3.0
            positive: "rate_mod_freq_hz", 0.8
        endPause: "Run", 1
        presetName$ = "RateMod"
    elsif mode = 4
        beginPause: "Swarm / Chorus Settings"
            positive: "base_delay_ms", 5.0
            positive: "modulation_depth", 0.08
            positive: "base_rate_hz", 8.0
            natural: "number_of_layers", 6
            positive: "layer_spread_hz", 0.5
        endPause: "Run", 1
        presetName$ = "Swarm"
    elsif mode = 5
        beginPause: "Enveloped Vibrato Settings"
            positive: "base_delay_ms", 6.0
            positive: "modulation_depth", 0.15
            positive: "base_rate_hz", 5.5
            positive: "attack_time_sec", 0.5
            positive: "release_time_sec", 0.5
        endPause: "Run", 1
        presetName$ = "Enveloped"
    elsif mode = 6
        beginPause: "Rotary Speaker Settings"
            positive: "base_delay_ms", 5.0
            positive: "modulation_depth", 0.10
            positive: "base_rate_hz", 5.0
            positive: "rotary_AM_Depth", 0.4
        endPause: "Run", 1
        presetName$ = "Rotary"
    elsif mode = 7
        beginPause: "Tape (Wow & Flutter) Settings"
            positive: "base_delay_ms", 5.0
            positive: "wow_Rate_Hz", 0.5
            positive: "wow_Depth", 0.15
            positive: "flutter_Rate_Hz", 6.0
            positive: "flutter_Depth", 0.05
        endPause: "Run", 1
        presetName$ = "Tape"
    endif

else
    # Load hardcoded presets
    
    if preset = 2
        # Classic Vocal
        mode = 1
        base_delay_ms = 5.0
        modulation_depth = 0.08
        base_rate_hz = 5.5
        presetName$ = "ClassicVocal"
        
    elsif preset = 3
        # Subtle Warmth
        mode = 1
        base_delay_ms = 3.0
        modulation_depth = 0.04
        base_rate_hz = 4.0
        presetName$ = "SubtleWarmth"
        
    elsif preset = 4
        # Leslie Fast
        mode = 6
        base_delay_ms = 5.0
        modulation_depth = 0.12
        base_rate_hz = 6.8
        rotary_AM_Depth = 0.5
        presetName$ = "LeslieFast"
        
    elsif preset = 5
        # Leslie Slow
        mode = 6
        base_delay_ms = 8.0
        modulation_depth = 0.15
        base_rate_hz = 1.2
        rotary_AM_Depth = 0.3
        presetName$ = "LeslieSlow"
        
    elsif preset = 6
        # Ghostly Chirp
        mode = 2
        base_delay_ms = 6.0
        modulation_depth = 0.15
        base_rate_hz = 2.0
        sweep_rate_hz_per_sec = 3.0
        presetName$ = "GhostlyChirp"
        
    elsif preset = 7
        # Drunk Tape
        mode = 3
        base_delay_ms = 10.0
        modulation_depth = 0.2
        base_rate_hz = 0.5
        rate_sensitivity = 4.0
        rate_mod_freq_hz = 0.2
        presetName$ = "DrunkTape"
        
    elsif preset = 8
        # Insect Swarm
        mode = 4
        base_delay_ms = 5.0
        modulation_depth = 0.08
        base_rate_hz = 8.0
        number_of_layers = 8
        layer_spread_hz = 1.5
        presetName$ = "InsectSwarm"
        
    elsif preset = 9
        # Fade-In
        mode = 5
        base_delay_ms = 6.0
        modulation_depth = 0.15
        base_rate_hz = 5.0
        attack_time_sec = 1.0
        release_time_sec = 0.1
        presetName$ = "FadeIn"
        
    elsif preset = 10
        # Vintage Cassette
        mode = 7
        base_delay_ms = 5.0
        wow_Rate_Hz = 0.8
        wow_Depth = 0.1
        flutter_Rate_Hz = 12.0
        flutter_Depth = 0.03
        presetName$ = "VintageCassette"
        
    elsif preset = 11
        # Old Reel-to-Reel
        mode = 7
        base_delay_ms = 8.0
        wow_Rate_Hz = 0.3
        wow_Depth = 0.2
        flutter_Rate_Hz = 4.0
        flutter_Depth = 0.05
        presetName$ = "ReelToReel"
        
    elsif preset = 12
        # Damaged Tape
        mode = 7
        base_delay_ms = 10.0
        wow_Rate_Hz = 1.5
        wow_Depth = 0.3
        flutter_Rate_Hz = 15.0
        flutter_Depth = 0.1
        presetName$ = "DamagedTape"
        
    elsif preset = 13
        # Warped Vinyl
        mode = 7
        base_delay_ms = 12.0
        wow_Rate_Hz = 0.2
        wow_Depth = 0.25
        flutter_Rate_Hz = 0.0
        flutter_Depth = 0.0
        presetName$ = "WarpedVinyl"
        
    elsif preset = 14
        # VHS Tracking
        mode = 7
        base_delay_ms = 4.0
        wow_Rate_Hz = 2.0
        wow_Depth = 0.05
        flutter_Rate_Hz = 25.0
        flutter_Depth = 0.08
        presetName$ = "VHSTracking"
    endif
endif

# Get mode name
if mode = 1
    modeName$ = "Standard"
elsif mode = 2
    modeName$ = "Chirped"
elsif mode = 3
    modeName$ = "RateMod"
elsif mode = 4
    modeName$ = "Swarm"
elsif mode = 5
    modeName$ = "Enveloped"
elsif mode = 6
    modeName$ = "Rotary"
elsif mode = 7
    modeName$ = "Tape"
endif

# === Info ===
writeInfoLine: "=== Unified Multi-Mode Vibrato v2.1 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# PROCESSING ENGINE
# ============================================================

appendInfoLine: "Processing (", modeName$, " mode)..."

base = round(base_delay_ms * sr / 1000)

# Create output copy
selectObject: original
Copy: original_name$ + "_vib_" + presetName$
result = selected("Sound")

# Build formula strings for object ID reference
orig_str$ = string$(original)

if mode = 1
    # STANDARD
    appendInfoLine: "  Rate: ", base_rate_hz, " Hz, Depth: ", modulation_depth
    
    base_str$ = string$(base)
    depth_str$ = string$(modulation_depth)
    rate_str$ = string$(base_rate_hz)
    
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x)))))]"

elsif mode = 2
    # CHIRPED
    appendInfoLine: "  Rate: ", base_rate_hz, " Hz, Sweep: ", sweep_rate_hz_per_sec, " Hz/s"
    
    base_str$ = string$(base)
    depth_str$ = string$(modulation_depth)
    rate_str$ = string$(base_rate_hz)
    sweep_str$ = string$(sweep_rate_hz_per_sec)
    
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * sin(2 * pi * (" + rate_str$ + " * x + 0.5 * " + sweep_str$ + " * x^2)))))]"

elsif mode = 3
    # RATE MOD
    appendInfoLine: "  Base rate: ", base_rate_hz, " Hz, Mod freq: ", rate_mod_freq_hz, " Hz"
    
    base_str$ = string$(base)
    depth_str$ = string$(modulation_depth)
    rate_str$ = string$(base_rate_hz)
    sens_str$ = string$(rate_sensitivity)
    modfreq_str$ = string$(rate_mod_freq_hz)
    
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * sin(2 * pi * (" + rate_str$ + " + " + sens_str$ + " * sin(2 * pi * " + modfreq_str$ + " * x)) * x))))]"

elsif mode = 4
    # SWARM (Additive layers)
    appendInfoLine: "  Layers: ", number_of_layers, ", Base rate: ", base_rate_hz, " Hz, Spread: ", layer_spread_hz, " Hz"
    
    # Start with silence
    Formula: ~ 0
    
    base_str$ = string$(base)
    depth_str$ = string$(modulation_depth)
    weight = 1 / number_of_layers
    weight_str$ = string$(weight)
    
    for d from 1 to number_of_layers
        current_rate = base_rate_hz + (d - 1) * layer_spread_hz
        current_phase = d * (2 * pi / number_of_layers)
        rate_str$ = string$(current_rate)
        phase_str$ = string$(current_phase)
        
        Formula: "self + object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x + " + phase_str$ + ")))))] * " + weight_str$
    endfor

elsif mode = 5
    # ENVELOPED
    appendInfoLine: "  Attack: ", attack_time_sec, " s, Release: ", release_time_sec, " s"
    
    base_str$ = string$(base)
    depth_str$ = string$(modulation_depth)
    rate_str$ = string$(base_rate_hz)
    attack_str$ = string$(attack_time_sec)
    release_str$ = string$(release_time_sec)
    dur_str$ = string$(duration)
    
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * max(0, min(1, min(x/" + attack_str$ + ", (" + dur_str$ + " - x)/" + release_str$ + "))) * sin(2 * pi * " + rate_str$ + " * x))))]"

elsif mode = 6
    # ROTARY (PM + AM)
    appendInfoLine: "  Rate: ", base_rate_hz, " Hz, AM depth: ", rotary_AM_Depth
    
    base_str$ = string$(base)
    depth_str$ = string$(modulation_depth)
    rate_str$ = string$(base_rate_hz)
    am_str$ = string$(rotary_AM_Depth)
    
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x)))))] * (1 - " + am_str$ + " * 0.5 * (1 + sin(2 * pi * " + rate_str$ + " * x + 1.57)))"

elsif mode = 7
    # TAPE (WOW & FLUTTER)
    appendInfoLine: "  Wow: ", wow_Rate_Hz, " Hz @ ", wow_Depth, ", Flutter: ", flutter_Rate_Hz, " Hz @ ", flutter_Depth
    
    base_str$ = string$(base)
    wowRate_str$ = string$(wow_Rate_Hz)
    wowDepth_str$ = string$(wow_Depth)
    flutterRate_str$ = string$(flutter_Rate_Hz)
    flutterDepth_str$ = string$(flutter_Depth)
    
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + wowDepth_str$ + " * sin(2 * pi * " + wowRate_str$ + " * x) + " + flutterDepth_str$ + " * sin(2 * pi * " + flutterRate_str$ + " * x)))))]"

endif

# Scale output
selectObject: result
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Multi-Mode Vibrato: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", modeName$
    Text bottom: "yes", "Time (s)"
    
    # Mode-specific visualization
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.8, 3.9
    
    vizDur = min(2, duration)
    nPoints = 300
    
    Axes: 0, vizDur, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -1.2, 1.2
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, vizDur, 0
    Solid line
    
    # Draw modulation based on mode
    Colour: "{0.5, 0.6, 0.7}"
    Line width: 1.5
    
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        
        if mode = 1
            # Standard
            mod1 = modulation_depth * sin(2 * pi * base_rate_hz * t1)
            mod2 = modulation_depth * sin(2 * pi * base_rate_hz * t2)
        elsif mode = 2
            # Chirped
            phase1 = 2 * pi * (base_rate_hz * t1 + 0.5 * sweep_rate_hz_per_sec * t1^2)
            phase2 = 2 * pi * (base_rate_hz * t2 + 0.5 * sweep_rate_hz_per_sec * t2^2)
            mod1 = modulation_depth * sin(phase1)
            mod2 = modulation_depth * sin(phase2)
        elsif mode = 3
            # Rate mod
            rate1 = base_rate_hz + rate_sensitivity * sin(2 * pi * rate_mod_freq_hz * t1)
            rate2 = base_rate_hz + rate_sensitivity * sin(2 * pi * rate_mod_freq_hz * t2)
            mod1 = modulation_depth * sin(2 * pi * rate1 * t1)
            mod2 = modulation_depth * sin(2 * pi * rate2 * t2)
        elsif mode = 4
            # Swarm (sum of layers)
            mod1 = 0
            mod2 = 0
            for d from 1 to number_of_layers
                layerRate = base_rate_hz + (d - 1) * layer_spread_hz
                layerPhase = d * (2 * pi / number_of_layers)
                mod1 = mod1 + modulation_depth * sin(2 * pi * layerRate * t1 + layerPhase) / number_of_layers
                mod2 = mod2 + modulation_depth * sin(2 * pi * layerRate * t2 + layerPhase) / number_of_layers
            endfor
        elsif mode = 5
            # Enveloped
            env1 = min(t1 / attack_time_sec, (duration - t1) / release_time_sec)
            env2 = min(t2 / attack_time_sec, (duration - t2) / release_time_sec)
            if env1 > 1
                env1 = 1
            endif
            if env1 < 0
                env1 = 0
            endif
            if env2 > 1
                env2 = 1
            endif
            if env2 < 0
                env2 = 0
            endif
            mod1 = modulation_depth * env1 * sin(2 * pi * base_rate_hz * t1)
            mod2 = modulation_depth * env2 * sin(2 * pi * base_rate_hz * t2)
        elsif mode = 6
            # Rotary (show both PM and AM)
            mod1 = modulation_depth * sin(2 * pi * base_rate_hz * t1)
            mod2 = modulation_depth * sin(2 * pi * base_rate_hz * t2)
        elsif mode = 7
            # Tape (wow + flutter)
            mod1 = wow_Depth * sin(2 * pi * wow_Rate_Hz * t1) + flutter_Depth * sin(2 * pi * flutter_Rate_Hz * t1)
            mod2 = wow_Depth * sin(2 * pi * wow_Rate_Hz * t2) + flutter_Depth * sin(2 * pi * flutter_Rate_Hz * t2)
        endif
        
        # Scale for display
        Draw line: t1, mod1 * 5, t2, mod2 * 5
    endfor
    Line width: 1
    
    # For rotary, also show AM envelope
    if mode = 6
        Colour: "{0.7, 0.5, 0.5}"
        Dotted line
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            am1 = rotary_AM_Depth * 0.5 * (1 + sin(2 * pi * base_rate_hz * t1 + 1.57))
            am2 = rotary_AM_Depth * 0.5 * (1 + sin(2 * pi * base_rate_hz * t2 + 1.57))
            Draw line: t1, am1, t2, am2
        endfor
        Solid line
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Modulation"
    Text bottom: "yes", "Time (s)"
    
    # Mode info box
    Select outer viewport: 0, 8, 4.2, 4.9
    Select inner viewport: 0.6, 7.6, 4.3, 4.8
    
    Axes: 0, 7, 0, 1
    
    # Draw mode boxes
    modeColors$[1] = "{0.7, 0.7, 0.8}"
    modeColors$[2] = "{0.7, 0.8, 0.7}"
    modeColors$[3] = "{0.8, 0.7, 0.7}"
    modeColors$[4] = "{0.8, 0.8, 0.7}"
    modeColors$[5] = "{0.7, 0.8, 0.8}"
    modeColors$[6] = "{0.8, 0.7, 0.8}"
    modeColors$[7] = "{0.8, 0.75, 0.7}"
    
    modeNames$[1] = "Std"
    modeNames$[2] = "Chirp"
    modeNames$[3] = "RateMod"
    modeNames$[4] = "Swarm"
    modeNames$[5] = "Env"
    modeNames$[6] = "Rotary"
    modeNames$[7] = "Tape"
    
    for m from 1 to 7
        xStart = (m - 1)
        if m = mode
            Paint rectangle: modeColors$[m], xStart, xStart + 1, 0, 1
            Colour: "Black"
            Line width: 2
            Draw rectangle: xStart, xStart + 1, 0, 1
            Line width: 1
        else
            Paint rectangle: "{0.9, 0.9, 0.9}", xStart, xStart + 1, 0, 1
            Colour: "{0.7, 0.7, 0.7}"
            Draw rectangle: xStart, xStart + 1, 0, 1
        endif
        
        Font size: 5
        if m = mode
            Colour: "Black"
        else
            Colour: "{0.6, 0.6, 0.6}"
        endif
        Text: xStart + 0.5, "centre", 0.5, "half", modeNames$[m]
    endfor
    
    Colour: "Black"
    
    # Parameters
    Select outer viewport: 0, 8, 5.0, 5.4
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    if mode = 1
        param$ = "Rate: " + fixed$(base_rate_hz, 1) + " Hz | Depth: " + fixed$(modulation_depth, 2) + " | Delay: " + fixed$(base_delay_ms, 1) + " ms"
    elsif mode = 2
        param$ = "Rate: " + fixed$(base_rate_hz, 1) + " Hz | Sweep: " + fixed$(sweep_rate_hz_per_sec, 1) + " Hz/s | Depth: " + fixed$(modulation_depth, 2)
    elsif mode = 3
        param$ = "Rate: " + fixed$(base_rate_hz, 1) + " Hz | Mod: " + fixed$(rate_mod_freq_hz, 1) + " Hz | Sens: " + fixed$(rate_sensitivity, 1)
    elsif mode = 4
        param$ = "Layers: " + string$(number_of_layers) + " | Rate: " + fixed$(base_rate_hz, 1) + " Hz | Spread: " + fixed$(layer_spread_hz, 1) + " Hz"
    elsif mode = 5
        param$ = "Rate: " + fixed$(base_rate_hz, 1) + " Hz | Attack: " + fixed$(attack_time_sec, 2) + " s | Release: " + fixed$(release_time_sec, 2) + " s"
    elsif mode = 6
        param$ = "Rate: " + fixed$(base_rate_hz, 1) + " Hz | PM: " + fixed$(modulation_depth, 2) + " | AM: " + fixed$(rotary_AM_Depth, 2)
    elsif mode = 7
        param$ = "Wow: " + fixed$(wow_Rate_Hz, 1) + " Hz @ " + fixed$(wow_Depth, 2) + " | Flutter: " + fixed$(flutter_Rate_Hz, 1) + " Hz @ " + fixed$(flutter_Depth, 2)
    endif
    
    Text: 0.5, "centre", 0.5, "half", param$
    
    Font size: 10
    Colour: "Black"
endif

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