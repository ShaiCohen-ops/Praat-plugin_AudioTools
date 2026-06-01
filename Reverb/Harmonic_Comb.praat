# ============================================================
# Praat AudioTools - Harmonic_Comb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Inharmonic Comb Morph - a stack of feedback comb resonators
#   whose teeth sit at h^beta * f0. Beta sets the spectral spacing:
#   beta = 1 is the harmonic series, beta < 1 compresses the partials
#   toward the fundamental, beta > 1 stretches them apart into bell /
#   gong-like inharmonicity. Beta glides linearly from Beta_start to
#   Beta_end across the sound, so the whole resonant structure bends
#   in real time (a spectral sweep). Teeth are weighted 1/h^2; the
#   fundamental (h=1) is the fixed anchor (1^beta = 1). The recursion
#   IS the resonance - this is a feedback comb, not feedforward.
#
# Changelog v0.2:
#   - Fixed delay formula
#   - Added bounds checking
#   - Fixed selection and formula syntax
#   - Added wet/dry mix control
#   - Added visualization
#
# Changelog v0.3:
#   - Reworked into an inharmonic comb with a linear beta morph:
#     delay[h] = round(fund / h^beta(col)), beta gliding Beta_start ->
#     Beta_end, baked per-sample into the feedback comb so the partials
#     sweep. h=1 stays the harmonic anchor (delay = fund).
#   - New Beta_start / Beta_end controls; presets recast as morph
#     trajectories.
#   - Fixed visualization centring (title + params on a 0..1 axis); the
#     delay panel now shows each tooth's start (light) -> end (dark) sweep.
#   - Wet/dry references the dry signal per-channel (object[id, row, col]).
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
    
    comment === Inharmonicity morph (beta) ===
    real Beta_start 1.0
    real Beta_end 1.3
    comment (1 = harmonic, <1 compressed, >1 stretched/bell)
    
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
    beta_start = 1.0
    beta_end = 1.05
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Comb
    number_of_harmonics = 7
    fundamental_delay_min_samp = 20
    fundamental_delay_max_samp = 100
    modulation_period = 1000
    beta_start = 1.0
    beta_end = 1.3
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Comb
    number_of_harmonics = 11
    fundamental_delay_min_samp = 15
    fundamental_delay_max_samp = 120
    modulation_period = 850
    beta_start = 0.85
    beta_end = 1.5
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Comb
    number_of_harmonics = 16
    fundamental_delay_min_samp = 10
    fundamental_delay_max_samp = 150
    modulation_period = 700
    beta_start = 0.7
    beta_end = 2.0
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

# Pre-calculate weights, phases, and start/end delays (for the morph + viz)
betaSpan = beta_end - beta_start
for h from 1 to number_of_harmonics
    harmWeight[h] = 1.0 / (h * h)
    harmPhase[h] = randomUniform(0, 2 * pi)
    harmDelayStart[h] = round(fundamental_delay / (h ^ beta_start))
    harmDelayEnd[h] = round(fundamental_delay / (h ^ beta_end))
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
appendInfoLine: "Beta morph: ", fixed$(beta_start, 2), " -> ", fixed$(beta_end, 2)
appendInfoLine: "Modulation period: ", modulation_period, " samples"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Tooth delays (start -> end samples):"
for h from 1 to number_of_harmonics
    appendInfoLine: "  h=", h, ": ", harmDelayStart[h], " -> ", harmDelayEnd[h], " samp, weight=", fixed$(harmWeight[h], 4)
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

# Apply each comb tooth with a per-sample morphing delay.
# delay(col) = round(fund / h^beta(col)), beta(col) glides start -> end.
# self[col-delay] reads the output -> this is a (resonant) feedback comb.
fund_str$ = string$(fundamental_delay)
bstart_str$ = string$(beta_start)
bspan_str$ = string$(betaSpan)
for h from 1 to number_of_harmonics
    weight = harmWeight[h]
    phase = harmPhase[h]
    
    weight_str$ = string$(weight)
    phase_str$ = string$(phase)
    mod_str$ = string$(modulation_period)
    h_str$ = string$(h)
    
    selectObject: wetSignal
    Formula: "if col > " + fund_str$ + " then self + " + weight_str$ + " * self[col - round(" + fund_str$ + " / (" + h_str$ + " ^ (" + bstart_str$ + " + " + bspan_str$ + " * (col-1)/(ncol-1))))] * cos(" + phase_str$ + " + 2*pi*col*" + h_str$ + "/" + mod_str$ + ") else self fi"
endfor

# Apply wet/dry mix
if dry_level > 0
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    orig_str$ = string$(original)
    
    selectObject: wetSignal
    Formula: "self * " + wet_str$ + " + object[" + orig_str$ + ", row, col] * " + dry_str$
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
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Inharmonic Comb Morph: " + originalName$ + " (" + presetName$ + ")"
    
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
    
    # Draw each tooth's start (light) and end (dark) delay as paired bars
    for h from 1 to number_of_harmonics
        Paint rectangle: "{0.75, 0.78, 0.88}", h - 0.35, h - 0.02, 0, harmDelayStart[h]
        Paint rectangle: "{0.35, 0.42, 0.62}", h + 0.02, h + 0.35, 0, harmDelayEnd[h]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay: start|end"
    Text bottom: "yes", "Harmonic #"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Fundamental: " + string$(fundamental_delay) + " samp (" + fixed$(fundamentalFreq, 1) + " Hz) | Harmonics: " + string$(number_of_harmonics) + " | Beta: " + fixed$(beta_start, 2) + "->" + fixed$(beta_end, 2) + " | Mod: " + string$(modulation_period)
    
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