# ============================================================
# Praat AudioTools - Math Operations
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Math Operations Between Two Sounds
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Math Operations Between Two Sounds

form Math Operations Between Sounds
    comment === GLOBAL PRESETS ===
    optionmenu Preset 1
        option Custom (manual settings)
        option Clean Add
        option Clean Multiply (Ring Mod)
        option Tremolo Effect
        option Crunch Mod (Arctan)
        option FM Synthesis
        option Double FM
        option Wavefold Distortion
        option Bitcrush Lo-Fi
        option Frequency Shifter
        option Hard Sync
        option Chaotic Mix
        option Spectral Blur
        option Phase Vocoder-like
        option Granular Scatter
        option Sqrt Domain
        option Vector Morph
        option Rectify Distortion
    comment === MANUAL SETTINGS (if Custom selected) ===
    comment Basic operations:
    optionmenu Operation 2
        option Add (+)
        option Subtract (-)
        option Multiply (*) [Ring Mod]
        option Divide (/)
        option Average
        option Minimum
        option Maximum
        option Absolute difference
        option XOR-like (sign mixing)
    comment Modulation & Waveshaping:
    # Renamed to strictly lowercase to match script logic
    optionmenu modulation_operation 3
        option None
        option AM: Sound1 * sin(Sound2)
        option AM: Sound1 * cos(Sound2)
        option FM-like: sin(Sound1) * Sound2
        option FM-like: cos(Sound1) * Sound2
        option Double FM: sin(S1) * sin(S2)
        option Soft clip: tan(S1 * S2)
        option Power mod: S1 ^ (S2/2)
        option Tremolo: S1 * (1 + S2)
    comment Non-linear & Spectral-like:
    optionmenu nonlinear_operation 4
        option None
        option Freq shift sim
        option AM depth control
        option Wavefold
        option Hard sync sim
        option Bitcrush 8-bit
        option Vector crossfade
        option Soft normalize mix
    comment Advanced transforms:
    optionmenu advanced_operation 5
        option None
        option Sqrt domain mix
        option Exp domain mix
        option Vector morph
        option Logistic chaos
        option Rectify & mix
        option Pseudo phase-vocoder
        option Random scatter
    positive Modulation_depth 1.0
    positive Nonlinear_intensity 0.5
    positive Output_scaling 1.0
    boolean Normalize_output 1
endform

# --- PRESET LOGIC ---
if preset > 1
    # 1. Reset everything to "None" (1) so we start fresh
    modulation_operation = 1
    nonlinear_operation = 1
    advanced_operation = 1
    output_scaling = 1.0
    
    # 2. Force Basic Operation to Add (1) as a fallback
    operation = 1

    # 3. Apply Specific Settings
    if preset = 2
        # Clean Add
        operation = 1
    elsif preset = 3
        # Clean Multiply
        operation = 3
    elsif preset = 4
        # Tremolo
        modulation_operation = 9; modulation_depth = 0.5
    elsif preset = 5
        # Crunch Mod
        modulation_operation = 7; modulation_depth = 2.0
    elsif preset = 6
        # FM Synthesis
        modulation_operation = 4; modulation_depth = 2.0
    elsif preset = 7
        # Double FM
        modulation_operation = 6; modulation_depth = 1.5
    elsif preset = 8
        # Wavefold
        nonlinear_operation = 4; nonlinear_intensity = 0.8
    elsif preset = 9
        # Bitcrush
        nonlinear_operation = 6; nonlinear_intensity = 0.5
    elsif preset = 10
        # Frequency Shifter
        nonlinear_operation = 2; nonlinear_intensity = 1.2
    elsif preset = 11
        # Hard Sync
        nonlinear_operation = 5; nonlinear_intensity = 0.9
    elsif preset = 12
        # Chaotic Mix
        advanced_operation = 5; nonlinear_intensity = 0.5
    elsif preset = 13
        # Spectral Blur
        nonlinear_operation = 8; nonlinear_intensity = 0.8
    elsif preset = 14
        # Phase Vocoder
        advanced_operation = 7; nonlinear_intensity = 0.5
    elsif preset = 15
        # Granular Scatter
        advanced_operation = 8; nonlinear_intensity = 0.6
    elsif preset = 16
        # Sqrt Domain
        advanced_operation = 2; nonlinear_intensity = 0.5
    elsif preset = 17
        # Vector Morph
        advanced_operation = 4; nonlinear_intensity = 0.5
    elsif preset = 18
        # Rectify
        advanced_operation = 6; nonlinear_intensity = 0.0
    endif
endif

# --- SOUND SELECTION ---
numberOfSelected = numberOfSelected("Sound")
if numberOfSelected <> 2
    exitScript: "Please select exactly 2 Sound objects"
endif

sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

selectObject: sound1
name1$ = selected$("Sound")
sr1 = Get sampling frequency
dur1 = Get total duration

selectObject: sound2
name2$ = selected$("Sound")
sr2 = Get sampling frequency
dur2 = Get total duration

if sr1 <> sr2
    exitScript: "Sampling rates must match (S1: " + string$(sr1) + " Hz, S2: " + string$(sr2) + " Hz)"
endif

min_dur = min(dur1, dur2)

# Extract equal parts
selectObject: sound1
Extract part: 0, min_dur, "rectangular", 1, "no"
sound1_part = selected("Sound")

selectObject: sound2
Extract part: 0, min_dur, "rectangular", 1, "no"
sound2_part = selected("Sound")

# Define result name
if preset = 1
    result_name$ = name1$ + "_" + operation$ + "_" + name2$
else
    result_name$ = name1$ + "_" + preset$ + "_" + name2$
endif

# Create result container
selectObject: sound1_part
Copy: result_name$
result = selected("Sound")

# --- CORE MATH PROCESSING ---
selectObject: result

# Priority Order: Advanced > Nonlinear > Modulation > Basic

if advanced_operation > 1
    # === ADVANCED TRANSFORMS ===
    depth = nonlinear_intensity
    if advanced_operation = 2
        # Sqrt Mix
        Formula... sqrt(abs(self) + 1e-10) * sqrt(abs(object[sound2_part]) + 1e-10) * 10
    elsif advanced_operation = 3
        # Log/Exp Mix
        Formula... exp(ln(abs(self) + 1e-10) + ln(abs(object[sound2_part]) + 1e-10)) * 0.1
    elsif advanced_operation = 4
        # Vector Morph
        Formula... self * (1 - 'depth') + object[sound2_part] * 'depth'
    elsif advanced_operation = 5
        # Logistic Chaos
        Formula... (self + object[sound2_part]) * (3.5 - 3.5 * abs(self) * abs(object[sound2_part]))
    elsif advanced_operation = 6
        # Rectify
        Formula... abs(self) - abs(object[sound2_part])
    elsif advanced_operation = 7
        # Phase Vocoder Sim
        Formula... self * cos(object[sound2_part] * 50 * pi) + object[sound2_part] * sin(self * 50 * pi)
    elsif advanced_operation = 8
        # Random Scatter
        Formula... (self + object[sound2_part]) * (0.8 + 0.4 * randomUniform(-1, 1))
    endif

elsif nonlinear_operation > 1
    # === NON-LINEAR OPERATIONS ===
    intensity = nonlinear_intensity
    if nonlinear_operation = 2
        # Freq Shifter
        Formula... self * cos(2 * pi * object[sound2_part] * 'intensity' * 100)
    elsif nonlinear_operation = 3
        # AM Depth
        Formula... self * (1 + object[sound2_part] * 'intensity')
    elsif nonlinear_operation = 4
        # Wavefold
        threshold = 0.5 + intensity
        Formula... if abs(self + object[sound2_part]) > 'threshold' then 'threshold' * (if (self + object[sound2_part]) >= 0 then 1 else -1 fi) - (self + object[sound2_part] - 'threshold' * (if (self + object[sound2_part]) >= 0 then 1 else -1 fi)) else self + object[sound2_part] fi
    elsif nonlinear_operation = 5
        # Hard Sync Sim
        Formula... if abs(object[sound2_part]) > abs(self) * 'intensity' then (if object[sound2_part] >= 0 then 1 else -1 fi) * abs(self) else self * object[sound2_part] fi
    elsif nonlinear_operation = 6
        # Bitcrush
        Formula... round((self + object[sound2_part]) * 8) / 8
    elsif nonlinear_operation = 7
        # Vector Crossfade
        Formula... self * (1 - 'intensity' * abs(object[sound2_part])) + object[sound2_part] * 'intensity'
    elsif nonlinear_operation = 8
        # Soft Normalize
        Formula... (self + object[sound2_part]) / (1 + 'intensity' * (abs(self) + abs(object[sound2_part])))
    endif

elsif modulation_operation > 1
    # === MODULATION OPERATIONS ===
    mod_depth = modulation_depth
    if modulation_operation = 2
        # Standard AM
        Formula... self * (0.5 + 0.5 * sin(object[sound2_part] * pi * 10 * 'mod_depth'))
    elsif modulation_operation = 3
        # Cosine AM
        Formula... self * (0.5 + 0.5 * cos(object[sound2_part] * pi * 10 * 'mod_depth'))
    elsif modulation_operation = 4
        # FM 1
        Formula... sin(self * pi * 5 * 'mod_depth') * object[sound2_part]
    elsif modulation_operation = 5
        # FM 2
        Formula... cos(self * pi * 5 * 'mod_depth') * object[sound2_part]
    elsif modulation_operation = 6
        # Double FM
        Formula... sin(self * pi * 5 * 'mod_depth') * sin(object[sound2_part] * pi * 5 * 'mod_depth')
    elsif modulation_operation = 7
        # Arctan (Crunchy)
        Formula... (2/pi) * arctan((self * object[sound2_part]) * 10 * 'mod_depth')
    elsif modulation_operation = 8
        # Power Mod
        Formula... if abs(object[sound2_part]) < 0.01 then self else (if self >= 0 then 1 else -1 fi) * (abs(self) ^ (1 + object[sound2_part] * 'mod_depth')) fi
    elsif modulation_operation = 9
        # Tremolo
        Formula... self * (1 + object[sound2_part] * 'mod_depth')
    endif

else
    # === BASIC OPERATIONS ===
    if operation = 1
        Formula... self + object[sound2_part]
    elsif operation = 2
        Formula... self - object[sound2_part]
    elsif operation = 3
        Formula... self * object[sound2_part]
    elsif operation = 4
        Formula... self / (object[sound2_part] + 1e-10)
    elsif operation = 5
        Formula... (self + object[sound2_part]) / 2
    elsif operation = 6
        Formula... min(self, object[sound2_part])
    elsif operation = 7
        Formula... max(self, object[sound2_part])
    elsif operation = 8
        Formula... abs(self - object[sound2_part])
    elsif operation = 9
        Formula... if self * object[sound2_part] < 0 then -(abs(self) + abs(object[sound2_part])) / 2 else (abs(self) + abs(object[sound2_part])) / 2 fi
    endif
endif

# --- POST PROCESSING ---
selectObject: result
if output_scaling <> 1.0
    Formula... self * output_scaling
endif

if normalize_output
    Scale peak: 0.99
endif

# Play the result
Play

# Clean up
removeObject: sound1_part, sound2_part

# Select result
selectObject: result