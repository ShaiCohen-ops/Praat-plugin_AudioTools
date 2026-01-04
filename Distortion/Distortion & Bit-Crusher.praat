# ============================================================
# Praat AudioTools - Distortion & Bit-Crusher
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distortion & Bit-Crusher
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Distortion & Bit-Crusher Suite (v1.0)
# A combined processor for Lo-Fi, Bit-Crushing, and Industrial Gating effects.
# Merges logic from 'crunchy.praat' and 'crunchy_2.praat'.

form Distortion & Bit-Crusher Suite
    comment Preset Selection:
    optionmenu Preset 1
        option Custom
        option -- BIT CRUSHER --
        option BC: Default (4-bit)
        option BC: Mild (8-bit)
        option BC: Lo-Fi Digital (3-bit)
        option BC: Heavy (2-bit)
        option -- HARSH DISTORTION --
        option HD: Balanced
        option HD: Light Drive
        option HD: Heavy Industrial
        option HD: Stutter Gate
    
    comment --- Mode Selection ---
    choice Effect_type 1
        button Bit Crusher
        button Harsh Distortion
    
    comment --- Bit Crusher Params ---
    positive Quantization_levels 4
    
    comment --- Harsh Distortion Params ---
    positive Base_amplitude 0.5
    positive Mod_amplitude 0.3
    positive Mod_frequency_hz 100
    positive Gate_period_s 0.05
    positive Gate_duty_cycle_s 0.025
    
    comment --- Output ---
    positive Scale_peak 0.99
    boolean Play_result 1
    boolean Keep_original 1
endform

# --- 1. APPLY PRESETS ---
# We automatically switch the Effect Type based on the preset chosen
if preset = 3
    # BC: Default
    effect_type = 1
    quantization_levels = 4
elsif preset = 4
    # BC: Mild
    effect_type = 1
    quantization_levels = 8
elsif preset = 5
    # BC: Lo-Fi
    effect_type = 1
    quantization_levels = 3
elsif preset = 6
    # BC: Heavy
    effect_type = 1
    quantization_levels = 2
elsif preset = 8
    # HD: Balanced
    effect_type = 2
    base_amplitude = 0.5
    mod_amplitude = 0.3
    mod_frequency_hz = 100
    gate_period_s = 0.05
    gate_duty_cycle_s = 0.025
elsif preset = 9
    # HD: Light Drive
    effect_type = 2
    base_amplitude = 0.4
    mod_amplitude = 0.2
    mod_frequency_hz = 80
    gate_period_s = 0.07
    gate_duty_cycle_s = 0.035
elsif preset = 10
    # HD: Industrial
    effect_type = 2
    base_amplitude = 0.7
    mod_amplitude = 0.4
    mod_frequency_hz = 150
    gate_period_s = 0.03
    gate_duty_cycle_s = 0.015
elsif preset = 11
    # HD: Stutter
    effect_type = 2
    base_amplitude = 0.6
    mod_amplitude = 0.25
    mod_frequency_hz = 90
    gate_period_s = 0.02
    gate_duty_cycle_s = 0.01
endif

# --- 2. SETUP ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
original_name$ = selected$("Sound")

if effect_type = 1
    suffix$ = "_Crushed"
    info$ = "Bit Crusher (" + string$(quantization_levels) + " levels)"
else
    suffix$ = "_Distorted"
    info$ = "Harsh Distortion (Mod: " + string$(mod_frequency_hz) + "Hz)"
endif

# --- 3. PROCESS ---
selectObject: sound
output = Copy: original_name$ + suffix$

if effect_type = 1
    # === BIT CRUSHER ALGORITHM ===
    # Formula: round(x * levels) / levels
    # This creates the "stepped" waveform typical of low-bit audio.
    
    q_str$ = string$(quantization_levels)
    Formula: "round(self * " + q_str$ + ") / " + q_str$

else
    # === HARSH DISTORTION ALGORITHM ===
    # Formula: Sign(x) * (Base + Mod) * Gate
    # This replaces the original waveform shape with a synthesized square/sine texture
    # modulated by the original signal's polarity (Zero-Crossing Distortion).
    
    # We construct the formula string to avoid parsing errors
    base$ = string$(base_amplitude)
    mod_amp$ = string$(mod_amplitude)
    mod_freq$ = string$(mod_frequency_hz)
    gate_per$ = string$(gate_period_s)
    gate_duty$ = string$(gate_duty_cycle_s)
    
    # 1. Sign Extraction: "if self > 0 then 1 else -1 fi"
    # 2. Amplitude Mod: "(base + mod_amp * sin(2*pi*mod_freq * x))"
    # 3. Gating: "if (x mod gate_per > gate_duty) then 1 else 0 fi"
    
    # Note: Added '2*pi' to modulation frequency for correct Hz interpretation
    Formula: "if self > 0 then 1 else -1 fi * (" + base$ + " + " + mod_amp$ + " * sin(2*pi*" + mod_freq$ + " * x)) * (if (x mod " + gate_per$ + " > " + gate_duty$ + ") then 1 else 0 fi)"
endif

# --- 4. FINALIZE ---
Scale peak: scale_peak

if play_result
    Play
endif

if keep_original = 0
    selectObject: sound
    Remove
endif

selectObject: output
writeInfoLine: "Distortion Suite Applied"
appendInfoLine: "Mode: ", info$
appendInfoLine: "Done."