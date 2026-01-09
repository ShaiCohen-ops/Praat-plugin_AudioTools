# ============================================================
# Praat AudioTools - Metamodulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Metamodulator - comprehensive 8-algorithm modulation toolkit:
#   Cubic/Quadratic phase distortion, Exponential/Logarithmic
#   frequency sweeps, Sinusoidal FM, Spiral FM, Time-varying
#   ring modulation, and Trembling ring modulation.
#
# Changelog v2.1:
#   - Modern formula syntax
#   - Added visualization
#   - Fixed xmax variable name conflict
# ============================================================

form Advanced Ring Modulator
    comment ========================================
    comment           PRESETS
    comment ========================================
    optionmenu Preset 1
        option Custom (Use Manual Settings)
        option --- Cubic Phase Distortion ---
        option Cubic: Mild Distortion
        option Cubic: Strong Distortion
        option Cubic: High Frequency
        option --- Exponential Sweep ---
        option ExpSweep: Slow
        option ExpSweep: Fast
        option ExpSweep: Narrow Range
        option --- Logarithmic Sweep ---
        option LogSweep: Descending Classic
        option LogSweep: Fast Descent
        option --- Quadratic Phase ---
        option Quad: Gentle Bend
        option Quad: Classic Sweep
        option Quad: Dramatic Warp
        option Quad: Reverse Bend
        option Quad: Extreme Distortion
        option Quad: Subtle Shimmer
        option --- Sinusoidal FM ---
        option SinFM: Classic
        option SinFM: Deep Modulation
        option --- Spiral FM ---
        option Spiral: Gentle
        option Spiral: Classic Vortex
        option Spiral: Intense Whirlpool
        option Spiral: Deep Rotation
        option Spiral: Hypnotic Spin
        option Spiral: Cosmic
        option --- Time-Varying (Chirp) ---
        option TimeVar: Subtle Shimmer
        option TimeVar: Rising Metallic
        option TimeVar: Sci-Fi Sweep
        option TimeVar: Laser Beam
        option TimeVar: Extreme Glitch
        option --- Trembling (Vibrato+Chirp) ---
        option Tremble: Gentle Warble
        option Tremble: Radio Interference
        option Tremble: Deep Space
        option Tremble: Vintage Synth
        option Tremble: Alien Voice

    comment 
    comment ========================================
    comment      MANUAL SETTINGS (Custom Mode)
    comment ========================================
    comment Select Algorithm:
    optionmenu Manual_Algorithm 1
        option 1. Cubic Phase Distortion
        option 2. Exponential Frequency Sweep
        option 3. Logarithmic Frequency Sweep
        option 4. Quadratic Phase Modulation
        option 5. Sinusoidal FM
        option 6. Spiral FM
        option 7. Time-Varying (Chirp)
        option 8. Trembling (Vibrato+Chirp)
    
    comment --- Frequency Parameters ---
    positive Carrier_Frequency_Hz 200
    comment (base frequency for modulation)
    
    positive Start_Frequency_Hz 100
    comment (for sweep algorithms 2 and 3)
    
    positive End_Frequency_Hz 800
    comment (for sweep algorithms 2 and 3)
    
    comment --- Modulation/Distortion Parameters ---
    real Modulation_Factor 2.0
    comment (depth/amount: cubic_factor, phase_curve, mod_depth, etc.)
    
    positive Modulation_Rate_Hz 5.0
    comment (LFO rate for algorithms 5, 6, 8)
    
    comment --- Output Control ---
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Check Selection
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sr = Get sampling frequency

# ============================================================
# PRESET LOGIC - Initialize with Manual Settings
# ============================================================
algo = manual_Algorithm
f0 = carrier_Frequency_Hz
f_start = start_Frequency_Hz
f_end = end_Frequency_Hz
mod_factor = modulation_Factor
mod_rate = modulation_Rate_Hz

# Override if preset is selected
if preset$ = "Cubic: Mild Distortion"
    algo = 1
    f0 = 100
    mod_factor = 1
elsif preset$ = "Cubic: Strong Distortion"
    algo = 1
    f0 = 200
    mod_factor = 4
elsif preset$ = "Cubic: High Frequency"
    algo = 1
    f0 = 300
    mod_factor = 2.5
elsif preset$ = "ExpSweep: Slow"
    algo = 2
    f_start = 100
    f_end = 600
elsif preset$ = "ExpSweep: Fast"
    algo = 2
    f_start = 50
    f_end = 1200
elsif preset$ = "ExpSweep: Narrow Range"
    algo = 2
    f_start = 200
    f_end = 400
elsif preset$ = "LogSweep: Descending Classic"
    algo = 3
    f_start = 800
    f_end = 50
elsif preset$ = "LogSweep: Fast Descent"
    algo = 3
    f_start = 1000
    f_end = 100
elsif preset$ = "Quad: Gentle Bend"
    algo = 4
    f0 = 150
    mod_factor = 0.3
elsif preset$ = "Quad: Classic Sweep"
    algo = 4
    f0 = 200
    mod_factor = 0.5
elsif preset$ = "Quad: Dramatic Warp"
    algo = 4
    f0 = 250
    mod_factor = 1.0
elsif preset$ = "Quad: Reverse Bend"
    algo = 4
    f0 = 180
    mod_factor = -0.4
elsif preset$ = "Quad: Extreme Distortion"
    algo = 4
    f0 = 300
    mod_factor = 1.5
elsif preset$ = "Quad: Subtle Shimmer"
    algo = 4
    f0 = 120
    mod_factor = 0.1
elsif preset$ = "SinFM: Classic"
    algo = 5
    f0 = 300
    mod_rate = 2
    mod_factor = 100
elsif preset$ = "SinFM: Deep Modulation"
    algo = 5
    f0 = 400
    mod_rate = 3
    mod_factor = 200
elsif preset$ = "Spiral: Gentle"
    algo = 6
    f0 = 200
    mod_rate = 0.5
    mod_factor = 80
elsif preset$ = "Spiral: Classic Vortex"
    algo = 6
    f0 = 250
    mod_rate = 0.8
    mod_factor = 150
elsif preset$ = "Spiral: Intense Whirlpool"
    algo = 6
    f0 = 300
    mod_rate = 1.2
    mod_factor = 200
elsif preset$ = "Spiral: Deep Rotation"
    algo = 6
    f0 = 150
    mod_rate = 0.6
    mod_factor = 120
elsif preset$ = "Spiral: Hypnotic Spin"
    algo = 6
    f0 = 400
    mod_rate = 1.5
    mod_factor = 180
elsif preset$ = "Spiral: Cosmic"
    algo = 6
    f0 = 180
    mod_rate = 0.7
    mod_factor = 250
elsif preset$ = "TimeVar: Subtle Shimmer"
    algo = 7
    f0 = 100
elsif preset$ = "TimeVar: Rising Metallic"
    algo = 7
    f0 = 200
elsif preset$ = "TimeVar: Sci-Fi Sweep"
    algo = 7
    f0 = 300
elsif preset$ = "TimeVar: Laser Beam"
    algo = 7
    f0 = 500
elsif preset$ = "TimeVar: Extreme Glitch"
    algo = 7
    f0 = 800
elsif preset$ = "Tremble: Gentle Warble"
    algo = 8
    f0 = 200
    mod_rate = 5
    mod_factor = 0.03
elsif preset$ = "Tremble: Radio Interference"
    algo = 8
    f0 = 440
    mod_rate = 25
    mod_factor = 0.08
elsif preset$ = "Tremble: Deep Space"
    algo = 8
    f0 = 100
    mod_rate = 10
    mod_factor = 0.1
elsif preset$ = "Tremble: Vintage Synth"
    algo = 8
    f0 = 300
    mod_rate = 20
    mod_factor = 0.06
elsif preset$ = "Tremble: Alien Voice"
    algo = 8
    f0 = 150
    mod_rate = 30
    mod_factor = 0.12
endif

# ============================================================
# Generate Suffix based on Algorithm
# ============================================================
if algo = 1
    algo_name$ = "Cubic"
elsif algo = 2
    algo_name$ = "ExpSweep"
elsif algo = 3
    algo_name$ = "LogSweep"
elsif algo = 4
    algo_name$ = "Quad"
elsif algo = 5
    algo_name$ = "SinFM"
elsif algo = 6
    algo_name$ = "Spiral"
elsif algo = 7
    algo_name$ = "TimeVar"
elsif algo = 8
    algo_name$ = "Tremble"
endif

# === Info ===
writeInfoLine: "=== Metamodulator ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Algorithm: ", algo, " - ", algo_name$
appendInfoLine: ""
if algo = 1 or algo = 4
    appendInfoLine: "Carrier: ", f0, " Hz"
    appendInfoLine: "Factor: ", mod_factor
elsif algo = 2 or algo = 3
    appendInfoLine: "Start freq: ", f_start, " Hz"
    appendInfoLine: "End freq: ", f_end, " Hz"
elsif algo = 5 or algo = 6
    appendInfoLine: "Carrier: ", f0, " Hz"
    appendInfoLine: "Mod rate: ", mod_rate, " Hz"
    appendInfoLine: "Mod depth: ", mod_factor
elsif algo = 7
    appendInfoLine: "Carrier: ", f0, " Hz"
elsif algo = 8
    appendInfoLine: "Carrier: ", f0, " Hz"
    appendInfoLine: "Vibrato rate: ", mod_rate, " Hz"
    appendInfoLine: "Vibrato depth: ", mod_factor
endif
appendInfoLine: ""

# ============================================================
# Copy Sound and Apply Algorithm
# ============================================================
selectObject: sound
Copy: name$ + "_" + algo_name$
result = selected("Sound")

# Get total duration for formulas (avoid xmax conflict)
selectObject: result
totalDuration = Get end time

# ============================================================
# ALGORITHM IMPLEMENTATION (Modern Syntax)
# ============================================================

appendInfoLine: "Applying ", algo_name$, " modulation..."

if algo = 1
    # 1. CUBIC PHASE DISTORTION
    Formula: ~ self * sin(2 * pi * f0 * x + mod_factor * (x^3))

elsif algo = 2
    # 2. EXPONENTIAL FREQUENCY SWEEP
    Formula: ~ self * sin(2 * pi * f_start * exp(ln(f_end/f_start) * x/totalDuration) * x)

elsif algo = 3
    # 3. LOGARITHMIC FREQUENCY SWEEP
    Formula: ~ self * sin(2 * pi * f_start * exp(-ln(f_start/f_end) * x/totalDuration) * x)

elsif algo = 4
    # 4. QUADRATIC PHASE MODULATION
    Formula: ~ self * sin(2 * pi * f0 * x + mod_factor * (x^2))

elsif algo = 5
    # 5. SINUSOIDAL FM
    Formula: ~ self * sin(2 * pi * (f0 + mod_factor * sin(2 * pi * mod_rate * x)) * x)

elsif algo = 6
    # 6. SPIRAL FM
    Formula: ~ self * sin(2 * pi * (f0 + mod_factor * sin(mod_rate * x) * x/totalDuration) * x)

elsif algo = 7
    # 7. TIME-VARYING RING MOD (chirp)
    Formula: ~ self * sin(2 * pi * f0 * x * x / 2)

elsif algo = 8
    # 8. TREMBLING RING MOD
    Formula: ~ self * sin(2 * pi * f0 * (1 + mod_factor * sin(2 * pi * mod_rate * x)) * x * x / 2)

endif

# ============================================================
# Finalize Output
# ============================================================
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Metamodulator: " + name$ + " (" + algo_name$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: sound
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
    Text left: "yes", algo_name$
    Text bottom: "yes", "Time (s)"
    
    # Modulation visualization
    Select outer viewport: 0, 8, 2.7, 4.0
    Select inner viewport: 0.6, 7.6, 2.8, 3.9
    
    modDisplayDur = min(1, duration)
    nModPoints = 300
    
    if algo = 1 or algo = 4
        # Phase distortion visualization
        if algo = 1
            maxPhase = mod_factor * (modDisplayDur^3)
        else
            maxPhase = mod_factor * (modDisplayDur^2)
        endif
        
        if maxPhase = 0
            maxPhase = 1
        endif
        
        Axes: 0, modDisplayDur, -abs(maxPhase) * 1.2, abs(maxPhase) * 1.2
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, -abs(maxPhase) * 1.2, abs(maxPhase) * 1.2
        
        Colour: "{0.7, 0.7, 0.7}"
        Dotted line
        Draw line: 0, 0, modDisplayDur, 0
        Solid line
        
        Colour: "{0.6, 0.5, 0.7}"
        Line width: 1.5
        for mp from 2 to nModPoints
            t1 = (mp - 2) / nModPoints * modDisplayDur
            t2 = (mp - 1) / nModPoints * modDisplayDur
            if algo = 1
                p1 = mod_factor * (t1^3)
                p2 = mod_factor * (t2^3)
            else
                p1 = mod_factor * (t1^2)
                p2 = mod_factor * (t2^2)
            endif
            Draw line: t1, p1, t2, p2
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Phase (rad)"
        
    elsif algo = 2 or algo = 3
        # Frequency sweep visualization
        minF = min(f_start, f_end)
        maxF = max(f_start, f_end)
        
        fMargin = (maxF - minF) * 0.1
        if fMargin < 10
            fMargin = 10
        endif
        
        Axes: 0, modDisplayDur, minF - fMargin, maxF + fMargin
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, minF - fMargin, maxF + fMargin
        
        Colour: "{0.6, 0.5, 0.7}"
        Line width: 1.5
        for mp from 2 to nModPoints
            t1 = (mp - 2) / nModPoints * modDisplayDur
            t2 = (mp - 1) / nModPoints * modDisplayDur
            if algo = 2
                freq1 = f_start * exp(ln(f_end/f_start) * t1/totalDuration)
                freq2 = f_start * exp(ln(f_end/f_start) * t2/totalDuration)
            else
                freq1 = f_start * exp(-ln(f_start/f_end) * t1/totalDuration)
                freq2 = f_start * exp(-ln(f_start/f_end) * t2/totalDuration)
            endif
            Draw line: t1, freq1, t2, freq2
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Freq (Hz)"
        
    elsif algo = 5 or algo = 6
        # FM visualization
        minF = f0 - abs(mod_factor)
        maxF = f0 + abs(mod_factor)
        
        fMargin = (maxF - minF) * 0.1
        if fMargin < 10
            fMargin = 10
        endif
        
        Axes: 0, modDisplayDur, minF - fMargin, maxF + fMargin
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, minF - fMargin, maxF + fMargin
        
        Colour: "{0.7, 0.7, 0.7}"
        Dotted line
        Draw line: 0, f0, modDisplayDur, f0
        Solid line
        
        Colour: "{0.6, 0.5, 0.7}"
        Line width: 1.5
        for mp from 2 to nModPoints
            t1 = (mp - 2) / nModPoints * modDisplayDur
            t2 = (mp - 1) / nModPoints * modDisplayDur
            if algo = 5
                freq1 = f0 + mod_factor * sin(2 * pi * mod_rate * t1)
                freq2 = f0 + mod_factor * sin(2 * pi * mod_rate * t2)
            else
                freq1 = f0 + mod_factor * sin(mod_rate * t1) * t1/totalDuration
                freq2 = f0 + mod_factor * sin(mod_rate * t2) * t2/totalDuration
            endif
            Draw line: t1, freq1, t2, freq2
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Freq (Hz)"
        
    elsif algo = 7 or algo = 8
        # Chirp visualization (instantaneous frequency)
        maxInstF = f0 * modDisplayDur
        if algo = 8
            maxInstF = f0 * (1 + abs(mod_factor)) * modDisplayDur
        endif
        
        if maxInstF < 10
            maxInstF = 100
        endif
        
        Axes: 0, modDisplayDur, 0, maxInstF * 1.1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, 0, maxInstF * 1.1
        
        Colour: "{0.6, 0.5, 0.7}"
        Line width: 1.5
        for mp from 2 to nModPoints
            t1 = (mp - 2) / nModPoints * modDisplayDur
            t2 = (mp - 1) / nModPoints * modDisplayDur
            if algo = 7
                freq1 = f0 * t1
                freq2 = f0 * t2
            else
                freq1 = f0 * (1 + mod_factor * sin(2 * pi * mod_rate * t1)) * t1
                freq2 = f0 * (1 + mod_factor * sin(2 * pi * mod_rate * t2)) * t2
            endif
            Draw line: t1, freq1, t2, freq2
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Inst. Freq"
    endif
    
    Text bottom: "yes", "Time (s)"
    
    # Algorithm info box
    Select outer viewport: 0, 8, 4.2, 5.0
    Select inner viewport: 0.6, 7.6, 4.3, 4.9
    
    Axes: 0, 8, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 8, 0, 2
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    if algo = 1
        Text: 4, "centre", 1.5, "half", "CUBIC: sin(2*pi*f0*t + factor*t^3)"
        Text: 4, "centre", 0.5, "half", "Harsh, edgy phase distortion"
    elsif algo = 2
        Text: 4, "centre", 1.5, "half", "EXP SWEEP: sin(2*pi*f_start*e^(ln(f_end/f_start)*t/T)*t)"
        Text: 4, "centre", 0.5, "half", "Exponentially rising frequency"
    elsif algo = 3
        Text: 4, "centre", 1.5, "half", "LOG SWEEP: sin(2*pi*f_start*e^(-ln(f_start/f_end)*t/T)*t)"
        Text: 4, "centre", 0.5, "half", "Logarithmically falling frequency"
    elsif algo = 4
        Text: 4, "centre", 1.5, "half", "QUADRATIC: sin(2*pi*f0*t + factor*t^2)"
        Text: 4, "centre", 0.5, "half", "Softer, tube-like distortion"
    elsif algo = 5
        Text: 4, "centre", 1.5, "half", "SIN FM: sin(2*pi*(f0 + depth*sin(2*pi*rate*t))*t)"
        Text: 4, "centre", 0.5, "half", "Classic FM synthesis"
    elsif algo = 6
        Text: 4, "centre", 1.5, "half", "SPIRAL: sin(2*pi*(f0 + depth*sin(rate*t)*t/T)*t)"
        Text: 4, "centre", 0.5, "half", "Evolving vortex modulation"
    elsif algo = 7
        Text: 4, "centre", 1.5, "half", "TIME-VAR: sin(2*pi*f0*t^2/2)"
        Text: 4, "centre", 0.5, "half", "Quadratic chirp"
    elsif algo = 8
        Text: 4, "centre", 1.5, "half", "TREMBLE: sin(2*pi*f0*(1 + d*sin(2*pi*r*t))*t^2/2)"
        Text: 4, "centre", 0.5, "half", "Chirp with vibrato"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    if algo = 1 or algo = 4
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Factor: " + fixed$(mod_factor, 2)
    elsif algo = 2 or algo = 3
        Text: 0.5, "centre", 0.5, "half", "Start: " + fixed$(f_start, 0) + " Hz | End: " + fixed$(f_end, 0) + " Hz"
    elsif algo = 5 or algo = 6
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Rate: " + fixed$(mod_rate, 1) + " Hz | Depth: " + fixed$(mod_factor, 0)
    elsif algo = 7
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Chirp rate: quadratic"
    elsif algo = 8
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Vibrato: " + fixed$(mod_rate, 0) + " Hz @ " + fixed$(mod_factor * 100, 1) + "%"
    endif
    
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