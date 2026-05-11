# ============================================================
# Praat AudioTools - Metamodulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Metamodulator - comprehensive 8-algorithm modulation toolkit.
#   Multiplies the source signal by one of eight synthesized
#   modulator waveforms:
#     1. Cubic Phase Distortion      sin(2pi*f0*t + k*t^3)
#     2. Exponential Frequency Sweep sin(2pi*f_start*exp(ln(f_end/f_start)*t/T)*t)
#     3. Logarithmic Frequency Sweep (descending variant of #2)
#     4. Quadratic Phase Modulation  sin(2pi*f0*t + k*t^2)
#     5. Sinusoidal FM               sin(2pi*(f0 + d*sin(2pi*r*t))*t)
#     6. Spiral FM                   sin(2pi*(f0 + d*sin(r*t)*t/T)*t)
#     7. Time-Varying (linear chirp) sin(pi*f0*t^2)
#     8. Trembling (vibrato + chirp) sin(pi*f0*(1 + d*sin(2pi*r*t))*t^2)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v2.2
#     for the same form parameters. Same Formula expressions for
#     all 8 algorithms. Same 33 presets with same values. Same
#     Scale peak.
#   - Form syntax modernized: both optionmenus use colon.
#   - Divider-option safety: v2.2's preset menu has --- divider
#     labels (e.g. "--- Cubic Phase Distortion ---") that look
#     like non-selectable headers but Praat lets the user pick
#     them. In v2.2 picking a divider silently fell through to
#     whatever was in Manual_Algorithm. v2.3 detects this and
#     exits with a clear message asking the user to pick a real
#     preset or use Custom.
#   - Show_spectrogram is now an opt-in form toggle (default OFF).
#     v2.2 always ran two `To Spectrogram` calls — one of which
#     was DEAD CODE (spec_orig was computed but never drawn).
#     v2.3 only computes the result spectrogram, and only when
#     the toggle is on. The dead spec_orig calculation is gone.
#   - Removed dead variable `sr = Get sampling frequency` that
#     v2.2 read but never used.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle (with formula displayed
#         per algorithm — promoted from v2.2's formula box)
#       Panel A (left, headline): modulation curve — the
#         algorithm-specific diagnostic (phase distortion,
#         frequency sweep, FM envelope, or chirp profile)
#       Panel B (right, headline): carrier preview at t=0
#         (3 cycles of the modulator waveform)
#       Panel C: zoom overlay (first 50 ms, original gray +
#         modulated purple)
#       Panel D: output waveform (full file) OR output
#         spectrogram (when Show_spectrogram = ON)
#       Panel E: light-grey summary stats bar matching the
#         suite-standard pattern
#   - Dropped the decorative `comment ===` form separators
#     to keep the form compact.
# Changelog v2.2:
#   - Enhanced visualization with spectrograms
#   - Added carrier signal preview
#   - Added zoomed waveform detail
# ============================================================

form Metamodulator v2.3
    optionmenu Preset: 1
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
    optionmenu Manual_Algorithm: 1
        option 1. Cubic Phase Distortion
        option 2. Exponential Frequency Sweep
        option 3. Logarithmic Frequency Sweep
        option 4. Quadratic Phase Modulation
        option 5. Sinusoidal FM
        option 6. Spiral FM
        option 7. Time-Varying (Chirp)
        option 8. Trembling (Vibrato+Chirp)
    positive Carrier_Frequency_Hz 200
    positive Start_Frequency_Hz 100
    positive End_Frequency_Hz 800
    real Modulation_Factor 2.0
    positive Modulation_Rate_Hz 5.0
    positive Scale_peak 0.95
    boolean Show_spectrogram 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Check Selection
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Detect divider preset selection. Praat optionmenus don't have
# non-selectable separators, so the user can accidentally pick
# a "--- Category ---" entry. v2.2 silently fell through to manual.
# v2.3 catches this and asks the user to choose a real preset.
if left$(preset$, 3) = "---"
    exitScript: "You selected a category divider (" + preset$ + ")." + newline$ + "Please pick a real preset, or choose 'Custom (Use Manual Settings)' to use the manual algorithm."
endif

sound = selected("Sound")
name$ = selected$("Sound")

selectObject: sound
duration = Get total duration

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
# Algorithm Names + Formulas (formula strings used in title bar)
# ============================================================
if algo = 1
    algo_name$ = "Cubic"
    algo_formula$ = "y = x . sin(2pi.f0.t + k.t^3)"
elsif algo = 2
    algo_name$ = "ExpSweep"
    algo_formula$ = "y = x . sin(2pi.f_s.exp(ln(f_e/f_s).t/T).t)"
elsif algo = 3
    algo_name$ = "LogSweep"
    algo_formula$ = "y = x . sin(2pi.f_s.exp(-ln(f_s/f_e).t/T).t)"
elsif algo = 4
    algo_name$ = "Quad"
    algo_formula$ = "y = x . sin(2pi.f0.t + k.t^2)"
elsif algo = 5
    algo_name$ = "SinFM"
    algo_formula$ = "y = x . sin(2pi.(f0 + d.sin(2pi.r.t)).t)"
elsif algo = 6
    algo_name$ = "Spiral"
    algo_formula$ = "y = x . sin(2pi.(f0 + d.sin(r.t).t/T).t)"
elsif algo = 7
    algo_name$ = "TimeVar"
    algo_formula$ = "y = x . sin(pi.f0.t^2)"
elsif algo = 8
    algo_name$ = "Tremble"
    algo_formula$ = "y = x . sin(pi.f0.(1 + d.sin(2pi.r.t)).t^2)"
endif

# === Info ===
clearinfo
writeInfoLine: "=== Metamodulator v2.3 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Algorithm: ", algo, " - ", algo_name$
appendInfoLine: "Preset: ", preset$
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
# ALGORITHM IMPLEMENTATION (identical to v2.2)
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

# Final stats
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # ----------------------------------------------------------
    # Compute spectrogram ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrogram
        selectObject: result
        To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
        spec_result = selected("Spectrogram")
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##METAMODULATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
    # Build a compact parameter summary by algorithm class
    if algo = 1 or algo = 4
        paramStr$ = "f0 " + fixed$(f0, 0) + " Hz  |  k " + fixed$(mod_factor, 2)
    elsif algo = 2 or algo = 3
        paramStr$ = fixed$(f_start, 0) + " -> " + fixed$(f_end, 0) + " Hz"
    elsif algo = 5 or algo = 6
        paramStr$ = "f0 " + fixed$(f0, 0) + " Hz  |  rate " + fixed$(mod_rate, 1) + " Hz  |  depth " + fixed$(mod_factor, 0)
    elsif algo = 7
        paramStr$ = "f0 " + fixed$(f0, 0) + " Hz  (linear chirp)"
    else
        paramStr$ = "f0 " + fixed$(f0, 0) + " Hz  |  vibrato " + fixed$(mod_rate, 0) + " Hz @ " + fixed$(mod_factor * 100, 1) + "%"
    endif
    
    Text: 0.5, "centre", -0.22, "half",
        ... name$
        ... + "  |  " + algo_name$
        ... + "  |  " + paramStr$
        ... + "  |  " + fixed$(finalDur, 2) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: MODULATION CURVE  (left, headline)
    # Algorithm-specific diagnostic: phase trajectory for 1/4,
    # instantaneous frequency for 2/3/5/6, instantaneous freq
    # of chirp for 7/8.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    modDisplayDur = min(1, duration)
    nModPoints = 300
    
    if algo = 1 or algo = 4
        # Phase distortion (cubic or quadratic)
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
        
        Colour: "{0.55, 0.35, 0.78}"
        Line width: 1.8
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
        
        Colour: "{0.55, 0.35, 0.78}"
        Line width: 1.8
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
        
    elsif algo = 5 or algo = 6
        # FM visualization
        minF = f0 - abs(mod_factor) * 1.2
        maxF = f0 + abs(mod_factor) * 1.2
        
        Axes: 0, modDisplayDur, minF, maxF
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, modDisplayDur, minF, maxF
        
        Colour: "{0.85, 0.85, 0.85}"
        Draw line: 0, f0, modDisplayDur, f0
        
        Colour: "{0.55, 0.35, 0.78}"
        Line width: 1.8
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
        
        Colour: "{0.55, 0.35, 0.78}"
        Line width: 1.8
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
        
        yLabel$ = "Inst. Freq (Hz)"
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", yLabel$
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: CARRIER PREVIEW AT t=0  (right, headline)
    # Shows the actual modulator waveform shape (3 cycles).
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    # Pick a sensible carrier reference frequency for the preview
    if algo = 2 or algo = 3
        carrierFreq = f_start
    else
        carrierFreq = f0
    endif
    if carrierFreq < 10
        carrierFreq = 100
    endif
    
    carrierPeriod = 1 / carrierFreq
    carrierPreviewDur = carrierPeriod * 3
    nCarrierPts = 200
    
    Axes: 0, carrierPreviewDur * 1000, -1.1, 1.1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, carrierPreviewDur * 1000, -1.1, 1.1
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, carrierPreviewDur * 1000, 0
    Draw line: 0, 1, carrierPreviewDur * 1000, 1
    Draw line: 0, -1, carrierPreviewDur * 1000, -1
    
    # Draw the modulator waveform (instantaneous shape near t=0)
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1.8
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
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (ms)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    
    # Algorithm-specific title for Panel A
    if algo = 1
        panelATitle$ = "Phase trajectory: cubic"
    elsif algo = 2
        panelATitle$ = "Frequency sweep: exponential"
    elsif algo = 3
        panelATitle$ = "Frequency sweep: logarithmic"
    elsif algo = 4
        panelATitle$ = "Phase trajectory: quadratic"
    elsif algo = 5
        panelATitle$ = "Instantaneous freq: sinusoidal FM"
    elsif algo = 6
        panelATitle$ = "Instantaneous freq: spiral FM"
    elsif algo = 7
        panelATitle$ = "Instantaneous freq: linear chirp"
    else
        panelATitle$ = "Instantaneous freq: trembling chirp"
    endif
    
    Text: 2.10, "centre", 7.30, "half", panelATitle$
    Text: 6.10, "centre", 7.30, "half", "Modulator waveform (3 cycles @ " + fixed$(carrierFreq, 0) + " Hz)"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 50 ms)
    # Original (gray) + result (purple) overlaid.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.05
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: sound
    origPeak = Get absolute extremum: 0, zoomDur, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, zoomDur, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: 0, zoomDur, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original (gray, behind)
    selectObject: sound
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    
    # Result (purple, on top)
    selectObject: result
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1.3
    Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, purple = modulated)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM or SPECTROGRAM
    # Conditional on Show_spectrogram form toggle.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if show_spectrogram
        selectObject: spec_result
        Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Output spectrogram"
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        selectObject: result
        outPeakViz = Get absolute extremum: 0, 0, "None"
        if outPeakViz < 0.001
            outPeakViz = 0.001
        endif
        ampViz = outPeakViz * 1.15
        
        Axes: 0, finalDur, -ampViz, ampViz
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, finalDur, 0
        
        selectObject: result
        Colour: "{0.55, 0.35, 0.78}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Output (full file)"
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
    endif
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if show_spectrogram
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + algo_name$ + "##"
        ... + "  " + name$
        ... + "  |  Preset: " + preset$
        ... + "  |  " + paramStr$
    
    Text: 0.02, "left", 0.28, "half",
        ... algo_formula$
        ... + "  |  Scale peak: " + fixed$(scale_peak, 2)
        ... + "  |  Spectrogram: " + specStr$
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectrogram if computed
    if show_spectrogram
        removeObject: spec_result
    endif
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s, peak ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
