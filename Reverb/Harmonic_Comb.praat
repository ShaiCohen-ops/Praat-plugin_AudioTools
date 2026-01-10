# ============================================================
# Praat AudioTools - Harmonic_Comb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Comb Filter - applies comb filtering at harmonic
#   series intervals. Delays follow fundamental/h pattern
#   (like harmonic overtone series), weighted by 1/h² (inverse
#   square law like Fourier series). Creates metallic, resonant
#   spectral coloring. Different from Harmonic_Decay_Reverb
#   which creates echo/reverb effects.
#
# Changelog v0.2:
#   - Fixed delay formula (feedforward comb)
#   - Added bounds checking
#   - Fixed selection and formula syntax
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Harmonic Comb Filter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Comb
        option Medium Comb
        option Heavy Comb
        option Extreme Comb
    
    comment === Harmonic Parameters ===
    natural Number_of_harmonics 7
    positive Fundamental_delay_min_samp 20
    positive Fundamental_delay_max_samp 100
    
    comment === Modulation ===
    positive Modulation_period 1000
    comment (phase modulation period in samples)
    
    comment === Mix ===
    real Wet_dry_percent 50
    comment (0 = dry only, 100 = wet only)
    
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
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
nSamples = Get number of samples

# === Apply Presets ===
if preset = 2
    # Subtle Comb
    number_of_harmonics = 4
    fundamental_delay_min_samp = 30
    fundamental_delay_max_samp = 80
    modulation_period = 1200
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Comb
    number_of_harmonics = 7
    fundamental_delay_min_samp = 20
    fundamental_delay_max_samp = 100
    modulation_period = 1000
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Comb
    number_of_harmonics = 11
    fundamental_delay_min_samp = 15
    fundamental_delay_max_samp = 120
    modulation_period = 850
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Comb
    number_of_harmonics = 16
    fundamental_delay_min_samp = 10
    fundamental_delay_max_samp = 150
    modulation_period = 700
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Generate fundamental delay
fundamental_delay = round(randomUniform(fundamental_delay_min_samp, fundamental_delay_max_samp))

# Pre-calculate harmonic delays and weights
for h from 1 to number_of_harmonics
    harmDelay[h] = round(fundamental_delay / h)
    harmWeight[h] = 1.0 / (h * h)
    harmPhase[h] = randomUniform(0, 2 * pi)
endfor

# Calculate fundamental frequency
fundamentalFreq = sr / fundamental_delay

# === Info ===
writeInfoLine: "=== Harmonic Comb Filter ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Fundamental delay: ", fundamental_delay, " samples (", fixed$(fundamental_delay / sr * 1000, 2), " ms)"
appendInfoLine: "Fundamental frequency: ", fixed$(fundamentalFreq, 1), " Hz"
appendInfoLine: "Harmonics: ", number_of_harmonics
appendInfoLine: "Modulation period: ", modulation_period, " samples"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Harmonic delays:"
for h from 1 to number_of_harmonics
    appendInfoLine: "  h=", h, ": delay=", harmDelay[h], " samp (", fixed$(harmDelay[h] / sr * 1000, 2), "ms), weight=", fixed$(harmWeight[h], 4)
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create wet signal
selectObject: original
Copy: "wet_signal"
wetSignal = selected("Sound")

# Apply each harmonic comb
for h from 1 to number_of_harmonics
    delay = harmDelay[h]
    weight = harmWeight[h]
    phase = harmPhase[h]
    
    delay_str$ = string$(delay)
    weight_str$ = string$(weight)
    phase_str$ = string$(phase)
    mod_str$ = string$(modulation_period)
    h_str$ = string$(h)
    
    # Feedforward comb filter with phase modulation
    # y[n] = x[n] + weight * x[n-delay] * cos(phase + 2π*n*h/period)
    selectObject: wetSignal
    Formula: "if col > " + delay_str$ + " then self + " + weight_str$ + " * self[col - " + delay_str$ + "] * cos(" + phase_str$ + " + 2*pi*col*" + h_str$ + "/" + mod_str$ + ") else self fi"
endfor

# Apply wet/dry mix
if dry_level > 0
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    orig_str$ = string$(original)
    
    selectObject: wetSignal
    Formula: "self * " + wet_str$ + " + object[" + orig_str$ + "] * " + dry_str$
endif

selectObject: wetSignal
Scale peak: scale_peak
Rename: originalName$ + "_comb_" + presetName$
result = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Harmonic Comb Filter: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Comb " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Harmonic weights diagram
    Select outer viewport: 0, 4, 2.5, 4.0
    Select inner viewport: 0.6, 3.8, 2.6, 3.9
    
    Axes: 0, number_of_harmonics + 1, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, number_of_harmonics + 1, 0, 1.2
    
    # Draw harmonic weights as bars
    for h from 1 to number_of_harmonics
        # Color gradient
        r = 0.4 + h * 0.03
        g = 0.6
        b = 0.5
        
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", h - 0.35, h + 0.35, 0, harmWeight[h]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Weight (1/h²)"
    Text bottom: "yes", "Harmonic #"
    
    # Delay pattern diagram
    Select outer viewport: 4, 8, 2.5, 4.0
    Select inner viewport: 4.4, 7.6, 2.6, 3.9
    
    maxDelaySamp = fundamental_delay * 1.1
    
    Axes: 0, number_of_harmonics + 1, 0, maxDelaySamp
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, number_of_harmonics + 1, 0, maxDelaySamp
    
    # Draw delays as bars
    for h from 1 to number_of_harmonics
        r = 0.5
        g = 0.5 + h * 0.02
        b = 0.6
        
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", h - 0.35, h + 0.35, 0, harmDelay[h]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (samp)"
    Text bottom: "yes", "Harmonic #"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Fundamental: " + string$(fundamental_delay) + " samp (" + fixed$(fundamentalFreq, 1) + " Hz) | Harmonics: " + string$(number_of_harmonics) + " | Mod: " + string$(modulation_period)
    
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