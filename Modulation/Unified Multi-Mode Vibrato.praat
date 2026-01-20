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
# ============================================================

# ============================================================
# Praat AudioTools - Unified_Multi_Mode_Vibrato
# Version: 2.6 (Compact UI + Full Visualization)
# ============================================================

form Unified Multi-Mode Vibrato v2.6
    comment === PRESET & MODE ===
    optionmenu Preset 1
        option Custom (use settings below)
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
    
    optionmenu Mode 1
        option Standard
        option Chirped
        option Rate Mod
        option Swarm
        option Enveloped
        option Rotary
        option Tape (Wow & Flutter)
    
    comment === PARAMETERS ===
    positive Speed_Hz 5.0
    positive Depth_0to1 0.10
    positive Delay_ms 5.0
    
    comment === SMART KNOBS (Function depends on Mode) ===
    real Param_X 0.0
    real Param_Y 0.0
    
    comment === OUTPUT ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INITIALIZE
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# ============================================================
# PRESET MAPPING
# ============================================================

if preset > 1
    if preset = 2
        # Classic Vocal
        mode = 1
        delay_ms = 5.0
        depth_0to1 = 0.08
        speed_Hz = 5.5
        presetName$ = "ClassicVocal"
    elsif preset = 3
        # Subtle Warmth
        mode = 1
        delay_ms = 3.0
        depth_0to1 = 0.04
        speed_Hz = 4.0
        presetName$ = "SubtleWarmth"
    elsif preset = 4
        # Leslie Fast
        mode = 6
        delay_ms = 5.0
        depth_0to1 = 0.12
        speed_Hz = 6.8
        param_X = 0.5
        presetName$ = "LeslieFast"
    elsif preset = 5
        # Leslie Slow
        mode = 6
        delay_ms = 8.0
        depth_0to1 = 0.15
        speed_Hz = 1.2
        param_X = 0.3
        presetName$ = "LeslieSlow"
    elsif preset = 6
        # Ghostly Chirp
        mode = 2
        delay_ms = 6.0
        depth_0to1 = 0.15
        speed_Hz = 2.0
        param_X = 3.0
        presetName$ = "GhostlyChirp"
    elsif preset = 7
        # Drunk Tape
        mode = 3
        delay_ms = 10.0
        depth_0to1 = 0.2
        speed_Hz = 0.5
        param_X = 4.0
        param_Y = 0.2
        presetName$ = "DrunkTape"
    elsif preset = 8
        # Insect Swarm
        mode = 4
        delay_ms = 5.0
        depth_0to1 = 0.08
        speed_Hz = 8.0
        param_X = 8
        param_Y = 1.5
        presetName$ = "InsectSwarm"
    elsif preset = 9
        # Fade-In
        mode = 5
        delay_ms = 6.0
        depth_0to1 = 0.15
        speed_Hz = 5.0
        param_X = 1.0
        param_Y = 0.1
        presetName$ = "FadeIn"
    elsif preset = 10
        # Vintage Cassette
        mode = 7
        delay_ms = 5.0
        speed_Hz = 0.8
        depth_0to1 = 0.1
        param_X = 12.0
        param_Y = 0.03
        presetName$ = "VintageCassette"
    elsif preset = 11
        # Reel to Reel
        mode = 7
        delay_ms = 8.0
        speed_Hz = 0.3
        depth_0to1 = 0.2
        param_X = 4.0
        param_Y = 0.05
        presetName$ = "ReelToReel"
    elsif preset = 12
        # Damaged Tape
        mode = 7
        delay_ms = 10.0
        speed_Hz = 1.5
        depth_0to1 = 0.3
        param_X = 15.0
        param_Y = 0.1
        presetName$ = "DamagedTape"
    elsif preset = 13
        # Warped Vinyl
        mode = 7
        delay_ms = 12.0
        speed_Hz = 0.2
        depth_0to1 = 0.25
        param_X = 0.0
        param_Y = 0.0
        presetName$ = "WarpedVinyl"
    elsif preset = 14
        # VHS Tracking
        mode = 7
        delay_ms = 4.0
        speed_Hz = 2.0
        depth_0to1 = 0.05
        param_X = 25.0
        param_Y = 0.08
        presetName$ = "VHSTracking"
    endif
else
    presetName$ = "Custom"
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

# Info
writeInfoLine: "=== Unified Multi-Mode Vibrato v2.6 ==="
appendInfoLine: "Source: ", original_name$, " | Mode: ", modeName$

base = round(delay_ms * sr / 1000)
base_str$ = string$(base)
depth_str$ = string$(depth_0to1)
rate_str$ = string$(speed_Hz)

# Create output
selectObject: original
Copy: original_name$ + "_vib_" + presetName$
result = selected("Sound")
orig_str$ = string$(original)

# ============================================================
# PROCESSING ENGINE
# ============================================================

if mode = 1
    # Standard
    appendInfoLine: "Rate: ", speed_Hz, " Hz | Depth: ", depth_0to1
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x)))))]"

elsif mode = 2
    # Chirped
    sweep = param_X
    if sweep = 0
        sweep = 2.0
    endif
    sweep_str$ = string$(sweep)
    appendInfoLine: "Rate: ", speed_Hz, " Hz | Sweep: ", sweep, " Hz/s"
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * sin(2 * pi * (" + rate_str$ + " * x + 0.5 * " + sweep_str$ + " * x^2)))))]"

elsif mode = 3
    # Rate Mod
    sens = param_X
    if sens = 0
        sens = 3.0
    endif
    modFreq = param_Y
    if modFreq = 0
        modFreq = 0.8
    endif
    sens_str$ = string$(sens)
    modfreq_str$ = string$(modFreq)
    appendInfoLine: "Base Rate: ", speed_Hz, " Hz | Mod Freq: ", modFreq, " Hz"
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * sin(2 * pi * (" + rate_str$ + " + " + sens_str$ + " * sin(2 * pi * " + modfreq_str$ + " * x)) * x))))]"

elsif mode = 4
    # Swarm
    layers = round(param_X)
    if layers < 2
        layers = 6
    endif
    spread = param_Y
    if spread = 0
        spread = 0.5
    endif
    appendInfoLine: "Layers: ", layers, " | Spread: ", spread, " Hz"
    Formula: ~ 0
    weight = 1 / layers
    weight_str$ = string$(weight)
    for d from 1 to layers
        current_rate = speed_Hz + (d - 1) * spread
        current_phase = d * (2 * pi / layers)
        cur_rate_str$ = string$(current_rate)
        phase_str$ = string$(current_phase)
        Formula: "self + object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + cur_rate_str$ + " * x + " + phase_str$ + ")))))] * " + weight_str$
    endfor

elsif mode = 5
    # Enveloped
    atk = param_X
    if atk = 0
        atk = 0.5
    endif
    rel = param_Y
    if rel = 0
        rel = 0.5
    endif
    dur_str$ = string$(duration)
    atk_str$ = string$(atk)
    rel_str$ = string$(rel)
    appendInfoLine: "Attack: ", atk, " s | Release: ", rel, " s"
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * max(0, min(1, min(x/" + atk_str$ + ", (" + dur_str$ + " - x)/" + rel_str$ + "))) * sin(2 * pi * " + rate_str$ + " * x))))]"

elsif mode = 6
    # Rotary
    am = param_X
    if am = 0
        am = 0.4
    endif
    am_str$ = string$(am)
    appendInfoLine: "Rate: ", speed_Hz, " Hz | AM Depth: ", am
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x)))))] * (1 - " + am_str$ + " * 0.5 * (1 + sin(2 * pi * " + rate_str$ + " * x + 1.57)))"

elsif mode = 7
    # Tape
    fRate = param_X
    if fRate = 0
        fRate = 6.0
    endif
    fDepth = param_Y
    if fDepth = 0
        fDepth = 0.05
    endif
    fRate_str$ = string$(fRate)
    fDepth_str$ = string$(fDepth)
    appendInfoLine: "Wow: ", speed_Hz, " Hz | Flutter: ", fRate, " Hz"
    Formula: "object[" + orig_str$ + ", row, max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x) + " + fDepth_str$ + " * sin(2 * pi * " + fRate_str$ + " * x)))))]"

endif

selectObject: result
Scale peak: scale_peak

# ============================================================
# FULL VISUALIZATION (RESTORED)
# ============================================================

if draw_visualization
    Erase all
    
    # --- 1. Title ---
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Multi-Mode Vibrato: " + original_name$ + " (" + presetName$ + ")"
    
    # --- 2. Original Waveform ---
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # --- 3. Result Waveform ---
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", modeName$
    
    # --- 4. Modulation Graph ---
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.8, 3.9
    
    vizDur = min(2, duration)
    nPoints = 300
    
    Axes: 0, vizDur, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -1.2, 1.2
    
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, vizDur, 0
    Solid line
    
    Colour: "{0.5, 0.6, 0.7}"
    Line width: 1.5
    
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        
        # Calculate modulation curve based on mode
        if mode = 1
            # Standard
            mod1 = depth_0to1 * sin(2 * pi * speed_Hz * t1)
            mod2 = depth_0to1 * sin(2 * pi * speed_Hz * t2)
        elsif mode = 2
            # Chirped (uses 'sweep' variable from processing block)
            phase1 = 2 * pi * (speed_Hz * t1 + 0.5 * sweep * t1^2)
            phase2 = 2 * pi * (speed_Hz * t2 + 0.5 * sweep * t2^2)
            mod1 = depth_0to1 * sin(phase1)
            mod2 = depth_0to1 * sin(phase2)
        elsif mode = 3
            # Rate Mod (uses 'sens' and 'modFreq')
            r1 = speed_Hz + sens * sin(2 * pi * modFreq * t1)
            r2 = speed_Hz + sens * sin(2 * pi * modFreq * t2)
            mod1 = depth_0to1 * sin(2 * pi * r1 * t1)
            mod2 = depth_0to1 * sin(2 * pi * r2 * t2)
        elsif mode = 4
            # Swarm (uses 'layers' and 'spread')
            mod1 = 0
            mod2 = 0
            for d from 1 to layers
                lRate = speed_Hz + (d - 1) * spread
                lPhase = d * (2 * pi / layers)
                mod1 = mod1 + depth_0to1 * sin(2 * pi * lRate * t1 + lPhase) / layers
                mod2 = mod2 + depth_0to1 * sin(2 * pi * lRate * t2 + lPhase) / layers
            endfor
        elsif mode = 5
            # Enveloped (uses 'atk' and 'rel')
            env1 = min(t1 / atk, (duration - t1) / rel)
            env2 = min(t2 / atk, (duration - t2) / rel)
            env1 = max(0, min(1, env1))
            env2 = max(0, min(1, env2))
            mod1 = depth_0to1 * env1 * sin(2 * pi * speed_Hz * t1)
            mod2 = depth_0to1 * env2 * sin(2 * pi * speed_Hz * t2)
        elsif mode = 6
            # Rotary
            mod1 = depth_0to1 * sin(2 * pi * speed_Hz * t1)
            mod2 = depth_0to1 * sin(2 * pi * speed_Hz * t2)
        elsif mode = 7
            # Tape (uses 'fRate' and 'fDepth')
            mod1 = depth_0to1 * sin(2 * pi * speed_Hz * t1) + fDepth * sin(2 * pi * fRate * t1)
            mod2 = depth_0to1 * sin(2 * pi * speed_Hz * t2) + fDepth * sin(2 * pi * fRate * t2)
        endif
        
        Draw line: t1, mod1 * 5, t2, mod2 * 5
    endfor
    Line width: 1
    
    # Rotary AM overlay
    if mode = 6
        Colour: "{0.7, 0.5, 0.5}"
        Dotted line
        for p from 2 to nPoints
            t1 = (p - 2) / nPoints * vizDur
            t2 = (p - 1) / nPoints * vizDur
            am1 = am * 0.5 * (1 + sin(2 * pi * speed_Hz * t1 + 1.57))
            am2 = am * 0.5 * (1 + sin(2 * pi * speed_Hz * t2 + 1.57))
            Draw line: t1, am1, t2, am2
        endfor
        Solid line
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Modulation"
    
    # --- 5. Mode Box ---
    Select outer viewport: 0, 8, 4.2, 4.9
    Select inner viewport: 0.6, 7.6, 4.3, 4.8
    Axes: 0, 7, 0, 1
    
    # Mode names array
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
            Paint rectangle: "{0.7, 0.8, 0.9}", xStart, xStart + 1, 0, 1
            Colour: "Black"
            Line width: 2
            Draw rectangle: xStart, xStart + 1, 0, 1
            Line width: 1
        else
            Paint rectangle: "{0.9, 0.9, 0.9}", xStart, xStart + 1, 0, 1
            Colour: "{0.7, 0.7, 0.7}"
            Draw rectangle: xStart, xStart + 1, 0, 1
        endif
        
        Font size: 8
        if m = mode
            Colour: "Black"
        else
            Colour: "{0.6, 0.6, 0.6}"
        endif
        Text: xStart + 0.5, "centre", 0.5, "half", modeNames$[m]
    endfor
    
    Colour: "Black"
    Font size: 10
endif

# === Finish ===
selectObject: result

if play_result
    Play
endif