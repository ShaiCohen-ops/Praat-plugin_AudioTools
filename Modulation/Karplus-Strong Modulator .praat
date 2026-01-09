# ============================================================
# Praat AudioTools - Karplus_Strong_Modulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Karplus-Strong Modulator - applies the classic physical
#   modeling plucked-string algorithm as an audio effect.
#   Delay time is modulated by LFO for pitch-varying resonances.
#   Creates metallic, plucked, or sci-fi textures.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed comparison operators (== → =)
#   - Fixed object references (use IDs)
#   - Simplified formula construction
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
orig_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === Form ===
form Karplus-Strong Modulator
    comment Select a Sound object first
    
    comment === Preset ===
    choice Preset 1
        button Custom (use settings below)
        button Deep Bass Pluck
        button Sci-Fi Siren
        button Metallic Chime
        button Warp Drive Engine
    
    comment === Resonator ===
    positive KS_base_freq 220
    comment (Resonator frequency in Hz)
    
    comment === Modulation ===
    positive KS_mod_rate 0.5
    real KS_mod_depth 12
    comment (Depth in semitones)
    
    comment === Decay ===
    real KS_decay 0.95
    comment (0.99 = long sustain, 0.5 = short pluck)
    
    comment === Mix ===
    real KS_mix 0.5
    comment (0 = dry, 1 = wet)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Deep Bass Pluck
    kS_base_freq = 80
    kS_mod_rate = 0.2
    kS_mod_depth = 1.0
    kS_decay = 0.85
    kS_mix = 0.6
    presetName$ = "Bass"
elsif preset = 3
    # Sci-Fi Siren
    kS_base_freq = 440
    kS_mod_rate = 0.3
    kS_mod_depth = 12
    kS_decay = 0.96
    kS_mix = 0.5
    presetName$ = "SciFi"
elsif preset = 4
    # Metallic Chime
    kS_base_freq = 880
    kS_mod_rate = 6.0
    kS_mod_depth = 0.5
    kS_decay = 0.99
    kS_mix = 0.4
    presetName$ = "Chime"
elsif preset = 5
    # Warp Drive
    kS_base_freq = 150
    kS_mod_rate = 8.0
    kS_mod_depth = 24
    kS_decay = 0.92
    kS_mix = 0.8
    presetName$ = "Warp"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Karplus-Strong Modulator ==="
appendInfoLine: "Source: ", orig_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Base frequency: ", kS_base_freq, " Hz"
appendInfoLine: "Mod rate: ", kS_mod_rate, " Hz"
appendInfoLine: "Mod depth: ", kS_mod_depth, " semitones"
appendInfoLine: "Decay: ", kS_decay
appendInfoLine: "Mix: ", kS_mix
appendInfoLine: ""

# === Create Reference Copy ===
appendInfoLine: "Creating reference copy..."
selectObject: original
Copy: "KS_ref"
refSound = selected("Sound")

# === Create Output Container ===
selectObject: original
Copy: "KS_output"
outSound = selected("Sound")

# Zero it out
Formula: ~ 0

# === Prepare Constants ===
dt = 1 / sr
twoPi = 2 * pi

# === Apply Karplus-Strong Formula ===
appendInfoLine: "Applying Karplus-Strong modulation..."

# The formula:
# delay = 1 / (base_freq * 2^(depth * sin(2π * rate * x) / 12))
# output = input + decay * avg(self[t-delay], self[t-delay-dt])

selectObject: outSound
Formula: ~ object[refSound] + kS_decay * (self(x - 1/(kS_base_freq * 2^(kS_mod_depth * sin(twoPi * kS_mod_rate * x) / 12))) + self(x - 1/(kS_base_freq * 2^(kS_mod_depth * sin(twoPi * kS_mod_rate * x) / 12)) - dt)) / 2

# === Mix Dry/Wet ===
if kS_mix < 1.0
    appendInfoLine: "Mixing dry/wet (", kS_mix * 100, "% wet)..."
    Formula: ~ self * kS_mix + object[refSound] * (1 - kS_mix)
endif

# === Scale and Rename ===
selectObject: outSound
Scale peak: 0.95
Rename: orig_name$ + "_KS_" + presetName$
result = selected("Sound")

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Karplus-Strong Modulator: " + orig_name$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "KS Mod"
    Text bottom: "yes", "Time (s)"
    
    # Delay time modulation
    Select outer viewport: 0, 8, 2.7, 3.7
    Select inner viewport: 0.6, 7.6, 2.8, 3.6
    
    # Show ~3 seconds or full duration
    modDisplayDur = min(3, duration)
    
    # Calculate delay range
    minDelay = 1 / (kS_base_freq * 2^(kS_mod_depth / 12)) * 1000
    maxDelay = 1 / (kS_base_freq * 2^(-kS_mod_depth / 12)) * 1000
    baseDelay = 1 / kS_base_freq * 1000
    
    delayMargin = (maxDelay - minDelay) * 0.1
    
    Axes: 0, modDisplayDur, minDelay - delayMargin, maxDelay + delayMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, minDelay - delayMargin, maxDelay + delayMargin
    
    # Base delay line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, baseDelay, modDisplayDur, baseDelay
    Solid line
    
    # Draw modulated delay
    Colour: "{0.5, 0.7, 0.6}"
    Line width: 1.5
    nModPoints = 300
    for mp from 2 to nModPoints
        t1 = (mp - 2) / nModPoints * modDisplayDur
        t2 = (mp - 1) / nModPoints * modDisplayDur
        d1 = 1 / (kS_base_freq * 2^(kS_mod_depth * sin(twoPi * kS_mod_rate * t1) / 12)) * 1000
        d2 = 1 / (kS_base_freq * 2^(kS_mod_depth * sin(twoPi * kS_mod_rate * t2) / 12)) * 1000
        Draw line: t1, d1, t2, d2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Time (s)"
    
    # Frequency modulation (corresponding pitch)
    Select outer viewport: 0, 8, 3.9, 4.9
    Select inner viewport: 0.6, 7.6, 4.0, 4.8
    
    minFreq = kS_base_freq * 2^(-kS_mod_depth / 12)
    maxFreq = kS_base_freq * 2^(kS_mod_depth / 12)
    freqMargin = (maxFreq - minFreq) * 0.1
    
    Axes: 0, modDisplayDur, minFreq - freqMargin, maxFreq + freqMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, minFreq - freqMargin, maxFreq + freqMargin
    
    # Base freq line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, kS_base_freq, modDisplayDur, kS_base_freq
    Solid line
    
    # Draw modulated frequency
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 1.5
    for mp from 2 to nModPoints
        t1 = (mp - 2) / nModPoints * modDisplayDur
        t2 = (mp - 1) / nModPoints * modDisplayDur
        f1 = kS_base_freq * 2^(kS_mod_depth * sin(twoPi * kS_mod_rate * t1) / 12)
        f2 = kS_base_freq * 2^(kS_mod_depth * sin(twoPi * kS_mod_rate * t2) / 12)
        Draw line: t1, f1, t2, f2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Karplus-Strong diagram
    Select outer viewport: 0, 8, 5.1, 5.9
    Select inner viewport: 0.6, 7.6, 5.2, 5.8
    
    Axes: 0, 10, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 2
    
    # Input box
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.5, 2, 0.6, 1.4
    Colour: "Black"
    Font size: 5
    Text: 1.25, "centre", 1, "half", "Input"
    
    # Arrow
    Draw arrow: 2, 1, 3, 1
    
    # Delay box
    Paint rectangle: "{0.6, 0.8, 0.6}", 3, 5, 0.6, 1.4
    Text: 4, "centre", 1, "half", "Delay (1/f)"
    
    # Arrow
    Draw arrow: 5, 1, 6, 1
    
    # Average box
    Paint rectangle: "{0.6, 0.6, 0.8}", 6, 7.5, 0.6, 1.4
    Text: 6.75, "centre", 1, "half", "Avg"
    
    # Arrow to output
    Draw arrow: 7.5, 1, 8.5, 1
    
    # Output
    Paint rectangle: "{0.8, 0.7, 0.6}", 8.5, 9.5, 0.6, 1.4
    Text: 9, "centre", 1, "half", "Out"
    
    # Feedback arrow
    Colour: "{0.7, 0.5, 0.5}"
    Draw line: 7.5, 0.6, 7.5, 0.3
    Draw line: 7.5, 0.3, 3.5, 0.3
    Draw arrow: 3.5, 0.3, 3.5, 0.6
    
    Font size: 4
    Text: 5.5, "centre", 0.15, "half", "× decay"
    
    Colour: "Black"
    Font size: 6
    
    # Stats
    Select outer viewport: 0, 8, 6.0, 6.3
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(kS_base_freq, 0) + " Hz | Rate: " + fixed$(kS_mod_rate, 1) + " Hz | Depth: ±" + fixed$(kS_mod_depth, 0) + " st | Decay: " + fixed$(kS_decay, 2) + " | Mix: " + fixed$(kS_mix * 100, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: refSound

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