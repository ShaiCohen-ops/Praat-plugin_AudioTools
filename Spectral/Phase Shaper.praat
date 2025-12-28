# ============================================================
# Praat AudioTools - Phase Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Convolution-based sound design using custom impulse responses.
#   Generates various IRs (chirps, noise, resonators, glitches)
#   and convolves them with the input to create extreme textures.
#   Effects include dispersion, freeze, rhythmic smearing, and more.
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
    comment === Parameters ===
    positive Intensity 1.0
    comment (controls length, density, or aggression)
    comment === Output ===
    positive Scale_peak 0.95
    boolean Play_result 1
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

# Handle stereo
if num_channels > 1
    selectObject: original
    sound = Convert to mono
else
    selectObject: original
    sound = Copy: "working"
endif

writeInfoLine: "=== Phase Shaper ==="
appendInfoLine: "Mode: ", mode
appendInfoLine: "Intensity: ", intensity
appendInfoLine: ""

# === GENERATE IMPULSE RESPONSE ===
nyquist = original_sr / 2

if mode = 1
    # HYPER DISPERSION - sweeping chirp
    ir_dur = 3.0 * intensity
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "0.5 * sin(2*pi * (50 + (" + string$(nyquist) + " - 50)/2 * x/" + string$(ir_dur) + ") * x)"
    Formula: "self * (1 - x / " + string$(ir_dur) + ")"
    suffix$ = "_hyper"

elsif mode = 2
    # QUANTUM RAIN - gated noise bursts
    ir_dur = 2.0
    dens$ = string$(15 * intensity)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.5)"
    Formula: "self * (if sin(" + dens$ + " * x) > 0.9 then 1 else 0 fi) * exp(-2 * x)"
    suffix$ = "_rain"

elsif mode = 3
    # FRACTAL ZAP - FM synthesis texture
    ir_dur = 0.5
    mr$ = string$(500 * intensity)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "sin(2*pi * (20 + 1000 * x) * x) * sin(2*pi * " + mr$ + " * x)"
    Formula: "self * (1 - x / " + string$(ir_dur) + ")"
    suffix$ = "_fractal"

elsif mode = 4
    # REVERSE BLACK HOLE - exponential swell
    ir_dur = 1.0 * intensity
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.2)"
    Formula: "self * exp(5 * (x - " + string$(ir_dur) + "))"
    suffix$ = "_blackhole"

elsif mode = 5
    # ALIEN RESONATOR - inharmonic chord
    ir_dur = 1.0
    fb = 500 * intensity
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "(sin(2*pi*" + string$(fb) + "*x) + sin(2*pi*" + string$(fb*1.5) + "*x) + sin(2*pi*" + string$(fb*2.3) + "*x)) * exp(-5*x)"
    suffix$ = "_resonator"

elsif mode = 6
    # CYBER GLITCH - square wave chirp
    ir_dur = 0.5 * intensity
    freq_rate$ = string$(50 * intensity)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "round(sin(2*pi * (100 * x + " + freq_rate$ + " * x^2)))"
    Formula: "self * (1 - x / " + string$(ir_dur) + ")"
    suffix$ = "_glitch"

elsif mode = 7
    # BOUNCING BALL - accelerating impulses
    ir_dur = 1.0 * intensity
    speed$ = string$(200 * intensity)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "sin(2*pi * " + speed$ + " * x^3)"
    Formula: "if self > 0.9 then 1 else 0 fi"
    suffix$ = "_bounce"

elsif mode = 8
    # DEEP SPACE - low filtered noise
    ir_dur = 3.0
    Create Sound from formula: "IR_noise", 1, 0, ir_dur, original_sr, "randomGauss(0, 1)"
    noise_id = selected("Sound")
    filtered_id = Filter (pass Hann band): 0, 200, 100
    removeObject: noise_id
    selectObject: filtered_id
    Rename: "IR"
    Formula: "self * (1 - x / " + string$(ir_dur) + ")"
    suffix$ = "_space"

elsif mode = 9
    # SPECTRAL FREEZE - long noise smear
    ir_dur = 5.0 * intensity
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.1)"
    Formula: "self * (1 - x / " + string$(ir_dur) + ")"
    suffix$ = "_freeze"

elsif mode = 10
    # DEMON GROWL - AM modulated noise
    ir_dur = 1.0
    rate$ = string$(30 * intensity)
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.5) * sin(2*pi * " + rate$ + " * x)"
    suffix$ = "_demon"

elsif mode = 11
    # SHATTERED GLASS - bright chaotic bursts
    ir_dur = 0.3 * intensity
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "randomGauss(0, 0.8) * sin(2*pi * 8000 * x) * exp(-10 * x)"
    suffix$ = "_shatter"

elsif mode = 12
    # TAPE DETERIORATION - warped flutter
    ir_dur = 1.5 * intensity
    Create Sound from formula: "IR", 1, 0, ir_dur, original_sr, "sin(2*pi * (200 + 50*sin(2*pi*5*x)) * x) * exp(-3 * x)"
    suffix$ = "_tape"

endif

ir_id = selected("Sound")

appendInfoLine: "IR duration: ", fixed$(ir_dur, 2), " s"

# === CONVOLUTION ===
appendInfoLine: "Convolving..."

selectObject: sound
plusObject: ir_id
convolved = Convolve: "sum", "zero"
Rename: original_name$ + suffix$

# === FINALIZE ===
Scale peak: scale_peak

removeObject: ir_id, sound

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: convolved
if play_result
    Play
endif