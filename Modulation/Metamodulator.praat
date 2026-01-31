# ============================================================
# Praat AudioTools - Metamodulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Metamodulator - comprehensive 8-algorithm modulation toolkit:
#   Cubic/Quadratic phase distortion, Exponential/Logarithmic
#   frequency sweeps, Sinusoidal FM, Spiral FM, Time-varying
#   ring modulation, and Trembling ring modulation.
#
# Changelog v2.2:
#   - Enhanced visualization with spectrograms
#   - Added carrier signal preview
#   - Added zoomed waveform detail
# ============================================================

form Advanced Ring Modulator v2.2
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
    positive Start_Frequency_Hz 100
    positive End_Frequency_Hz 800
    
    comment --- Modulation/Distortion Parameters ---
    real Modulation_Factor 2.0
    positive Modulation_Rate_Hz 5.0
    
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
# PRESET LOGIC
# ============================================================
algo = manual_Algorithm
f0 = carrier_Frequency_Hz
f_start = start_Frequency_Hz
f_end = end_Frequency_Hz
mod_factor = modulation_Factor
mod_rate = modulation_Rate_Hz

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
# Algorithm Names
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
clearinfo
writeInfoLine: "=== Metamodulator v2.2 ==="
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

selectObject: result
totalDuration = Get end time

# ============================================================
# ALGORITHM IMPLEMENTATION
# ============================================================

appendInfoLine: "Applying ", algo_name$, " modulation..."

if algo = 1
    Formula: ~ self * sin(2 * pi * f0 * x + mod_factor * (x^3))
elsif algo = 2
    Formula: ~ self * sin(2 * pi * f_start * exp(ln(f_end/f_start) * x/totalDuration) * x)
elsif algo = 3
    Formula: ~ self * sin(2 * pi * f_start * exp(-ln(f_start/f_end) * x/totalDuration) * x)
elsif algo = 4
    Formula: ~ self * sin(2 * pi * f0 * x + mod_factor * (x^2))
elsif algo = 5
    Formula: ~ self * sin(2 * pi * (f0 + mod_factor * sin(2 * pi * mod_rate * x)) * x)
elsif algo = 6
    Formula: ~ self * sin(2 * pi * (f0 + mod_factor * sin(mod_rate * x) * x/totalDuration) * x)
elsif algo = 7
    Formula: ~ self * sin(2 * pi * f0 * x * x / 2)
elsif algo = 8
    Formula: ~ self * sin(2 * pi * f0 * (1 + mod_factor * sin(2 * pi * mod_rate * x)) * x * x / 2)
endif

selectObject: result
Scale peak: scale_peak

# ============================================================
# ENHANCED VISUALIZATION
# ============================================================
if draw_visualization
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Metamodulator: " + algo_name$ + "##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.2, "centre", -1.0, "half", name$ + " | " + fixed$(duration, 2) + " s"
    
    # === Original Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.7, 1.35
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # === Result Waveform ===
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.5, 2.15
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", algo_name$
    Text bottom: "yes", "Time (s)"
    
    # === Zoomed Detail (first 50ms) ===
    Select outer viewport: 0, 4, 2.3, 3.4
    Select inner viewport: 0.6, 3.7, 2.45, 3.3
    
    zoomEnd = min(0.05, duration)
    
    selectObject: sound
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, zoomEnd, 0, 0, "no", "Curve"
    
    selectObject: result
    Colour: "{0.6, 0.4, 0.7}"
    Draw: 0, zoomEnd, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Zoom: 0-50ms (gray=orig, purple=mod)"
    
    # === Carrier Signal Preview ===
    Select outer viewport: 4, 8, 2.3, 3.4
    Select inner viewport: 4.4, 7.7, 2.45, 3.3
    
    # Show 3 cycles of the carrier at t=0
    if algo = 1 or algo = 4 or algo = 5 or algo = 6
        carrierFreq = f0
    elsif algo = 2
        carrierFreq = f_start
    elsif algo = 3
        carrierFreq = f_start
    elsif algo = 7 or algo = 8
        carrierFreq = f0
    endif
    
    carrierPeriod = 1 / carrierFreq
    carrierPreviewDur = carrierPeriod * 3
    nCarrierPts = 200
    
    Axes: 0, carrierPreviewDur * 1000, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, carrierPreviewDur * 1000, -1.1, 1.1
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, carrierPreviewDur * 1000, 0
    
    # Draw carrier
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 1.5
    for cp from 2 to nCarrierPts
        t1 = (cp - 2) / nCarrierPts * carrierPreviewDur
        t2 = (cp - 1) / nCarrierPts * carrierPreviewDur
        
        if algo = 1
            y1 = sin(2 * pi * f0 * t1 + mod_factor * (t1^3))
            y2 = sin(2 * pi * f0 * t2 + mod_factor * (t2^3))
        elsif algo = 2
            y1 = sin(2 * pi * f_start * exp(ln(f_end/f_start) * t1/totalDuration) * t1)
            y2 = sin(2 * pi * f_start * exp(ln(f_end/f_start) * t2/totalDuration) * t2)
        elsif algo = 3
            y1 = sin(2 * pi * f_start * exp(-ln(f_start/f_end) * t1/totalDuration) * t1)
            y2 = sin(2 * pi * f_start * exp(-ln(f_start/f_end) * t2/totalDuration) * t2)
        elsif algo = 4
            y1 = sin(2 * pi * f0 * t1 + mod_factor * (t1^2))
            y2 = sin(2 * pi * f0 * t2 + mod_factor * (t2^2))
        elsif algo = 5
            y1 = sin(2 * pi * (f0 + mod_factor * sin(2 * pi * mod_rate * t1)) * t1)
            y2 = sin(2 * pi * (f0 + mod_factor * sin(2 * pi * mod_rate * t2)) * t2)
        elsif algo = 6
            y1 = sin(2 * pi * (f0 + mod_factor * sin(mod_rate * t1) * t1/totalDuration) * t1)
            y2 = sin(2 * pi * (f0 + mod_factor * sin(mod_rate * t2) * t2/totalDuration) * t2)
        elsif algo = 7
            y1 = sin(2 * pi * f0 * t1 * t1 / 2)
            y2 = sin(2 * pi * f0 * t2 * t2 / 2)
        elsif algo = 8
            y1 = sin(2 * pi * f0 * (1 + mod_factor * sin(2 * pi * mod_rate * t1)) * t1 * t1 / 2)
            y2 = sin(2 * pi * f0 * (1 + mod_factor * sin(2 * pi * mod_rate * t2)) * t2 * t2 / 2)
        endif
        
        Draw line: t1 * 1000, y1, t2 * 1000, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Carrier"
    Text bottom: "yes", "Time (ms)"
    Text top: "no", "Modulator Signal (3 cycles @ " + fixed$(carrierFreq, 0) + " Hz)"
    
    # === Modulation Curve ===
    Select outer viewport: 0, 4, 3.5, 4.8
    Select inner viewport: 0.6, 3.7, 3.65, 4.7
    
    modDisplayDur = min(1, duration)
    nModPoints = 300
    
    if algo = 1 or algo = 4
        # Phase distortion visualization
        if algo = 1
            maxPhase = abs(mod_factor * (modDisplayDur^3))
        else
            maxPhase = abs(mod_factor * (modDisplayDur^2))
        endif
        if maxPhase < 0.1
            maxPhase = 1
        endif
        
        Axes: 0, modDisplayDur, -maxPhase * 1.2, maxPhase * 1.2
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, modDisplayDur, -maxPhase * 1.2, maxPhase * 1.2
        
        Colour: "{0.85, 0.85, 0.85}"
        Draw line: 0, 0, modDisplayDur, 0
        
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
        
        yLabel$ = "Phase (rad)"
        plotTitle$ = "Phase Distortion"
        
    elsif algo = 2 or algo = 3
        # Frequency sweep
        minF = min(f_start, f_end)
        maxF = max(f_start, f_end)
        fMargin = (maxF - minF) * 0.15
        if fMargin < 20
            fMargin = 20
        endif
        
        Axes: 0, modDisplayDur, minF - fMargin, maxF + fMargin
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, modDisplayDur, minF - fMargin, maxF + fMargin
        
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
        
        yLabel$ = "Freq (Hz)"
        if algo = 2
            plotTitle$ = "Exponential Sweep"
        else
            plotTitle$ = "Logarithmic Sweep"
        endif
        
    elsif algo = 5 or algo = 6
        # FM visualization
        minF = f0 - abs(mod_factor) * 1.2
        maxF = f0 + abs(mod_factor) * 1.2
        
        Axes: 0, modDisplayDur, minF, maxF
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, modDisplayDur, minF, maxF
        
        Colour: "{0.85, 0.85, 0.85}"
        Draw line: 0, f0, modDisplayDur, f0
        
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
        
        yLabel$ = "Freq (Hz)"
        if algo = 5
            plotTitle$ = "Sinusoidal FM"
        else
            plotTitle$ = "Spiral FM"
        endif
        
    elsif algo = 7 or algo = 8
        # Chirp visualization
        maxInstF = f0 * modDisplayDur
        if algo = 8
            maxInstF = f0 * (1 + abs(mod_factor)) * modDisplayDur
        endif
        if maxInstF < 50
            maxInstF = 100
        endif
        
        Axes: 0, modDisplayDur, 0, maxInstF * 1.15
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, modDisplayDur, 0, maxInstF * 1.15
        
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
        
        yLabel$ = "Inst. Freq"
        if algo = 7
            plotTitle$ = "Time-Varying Chirp"
        else
            plotTitle$ = "Trembling Chirp"
        endif
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", yLabel$
    Text bottom: "yes", "Time (s)"
    Text top: "no", plotTitle$
    
    # === Spectrogram Comparison ===
    Select outer viewport: 4, 8, 3.5, 4.8
    Select inner viewport: 4.4, 7.7, 3.65, 4.7
    
    # Create spectrograms
    selectObject: sound
    To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    spec_orig = selected("Spectrogram")
    
    selectObject: result
    To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    spec_result = selected("Spectrogram")
    
    # Draw result spectrogram
    selectObject: spec_result
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output Spectrogram"
    
    removeObject: spec_orig, spec_result
    
    # === Algorithm Formula Box ===
    Select outer viewport: 0, 8, 4.9, 5.6
    Select inner viewport: 0.6, 7.7, 5.0, 5.5
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.97}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.4}"
    
    if algo = 1
        Text: 0.5, "centre", 0.65, "half", "CUBIC: y = x · sin(2π·f₀·t + k·t³)"
        Text: 0.5, "centre", 0.25, "half", "Harsh, metallic phase distortion"
    elsif algo = 2
        Text: 0.5, "centre", 0.65, "half", "EXP SWEEP: y = x · sin(2π·f₀·e^(ln(f₁/f₀)·t/T)·t)"
        Text: 0.5, "centre", 0.25, "half", "Rising frequency sweep"
    elsif algo = 3
        Text: 0.5, "centre", 0.65, "half", "LOG SWEEP: y = x · sin(2π·f₀·e^(-ln(f₀/f₁)·t/T)·t)"
        Text: 0.5, "centre", 0.25, "half", "Falling frequency sweep"
    elsif algo = 4
        Text: 0.5, "centre", 0.65, "half", "QUADRATIC: y = x · sin(2π·f₀·t + k·t²)"
        Text: 0.5, "centre", 0.25, "half", "Softer, tube-like distortion"
    elsif algo = 5
        Text: 0.5, "centre", 0.65, "half", "SIN FM: y = x · sin(2π·(f₀ + d·sin(2π·r·t))·t)"
        Text: 0.5, "centre", 0.25, "half", "Classic frequency modulation"
    elsif algo = 6
        Text: 0.5, "centre", 0.65, "half", "SPIRAL: y = x · sin(2π·(f₀ + d·sin(r·t)·t/T)·t)"
        Text: 0.5, "centre", 0.25, "half", "Evolving vortex modulation"
    elsif algo = 7
        Text: 0.5, "centre", 0.65, "half", "TIME-VAR: y = x · sin(π·f₀·t²)"
        Text: 0.5, "centre", 0.25, "half", "Linear chirp"
    elsif algo = 8
        Text: 0.5, "centre", 0.65, "half", "TREMBLE: y = x · sin(π·f₀·(1 + d·sin(2π·r·t))·t²)"
        Text: 0.5, "centre", 0.25, "half", "Chirp with vibrato"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # === Parameter Summary ===
    Select outer viewport: 0, 8, 5.7, 6.2
    Axes: 0, 1, 0, 1
    
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    if algo = 1 or algo = 4
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Factor: " + fixed$(mod_factor, 2)
    elsif algo = 2 or algo = 3
        Text: 0.5, "centre", 0.5, "half", "Start: " + fixed$(f_start, 0) + " Hz → End: " + fixed$(f_end, 0) + " Hz"
    elsif algo = 5 or algo = 6
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Rate: " + fixed$(mod_rate, 1) + " Hz | Depth: " + fixed$(mod_factor, 0) + " Hz"
    elsif algo = 7
        Text: 0.5, "centre", 0.5, "half", "Carrier: " + fixed$(f0, 0) + " Hz | Chirp: quadratic"
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

if play_result
    selectObject: result
    Play
endif

selectObject: result
