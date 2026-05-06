# ============================================================
# Praat AudioTools - Math_Operations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Math Operations Between Two Sounds - combines two audio
#   files using mathematical operations. Includes basic math
#   (add, multiply/ring mod, etc.), modulation (AM, FM),
#   nonlinear processing (wavefold, bitcrush), and advanced
#   transforms (vector morph, chaos, phase vocoder sim).
#   Select exactly 2 Sound objects before running.
#
# Changelog v0.2:
#   - Fixed formula syntax (Formula: ~)
#   - Fixed undefined variable errors
#   - Added visualization
#   - Added info output
# ============================================================

form Math Operations Between Sounds
    comment Select exactly 2 Sound objects first
    
    comment === Preset ===
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
    
    comment === Basic Operations ===
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
    
    comment === Modulation ===
    optionmenu Modulation_operation 1
        option None
        option AM: Sound1 * sin(Sound2)
        option AM: Sound1 * cos(Sound2)
        option FM-like: sin(Sound1) * Sound2
        option FM-like: cos(Sound1) * Sound2
        option Double FM: sin(S1) * sin(S2)
        option Soft clip: arctan(S1 * S2)
        option Power mod: S1 ^ (S2/2)
        option Tremolo: S1 * (1 + S2)
    
    comment === Nonlinear ===
    optionmenu Nonlinear_operation 1
        option None
        option Freq shift sim
        option AM depth control
        option Wavefold
        option Hard sync sim
        option Bitcrush 8-bit
        option Vector crossfade
        option Soft normalize mix
    
    comment === Advanced ===
    optionmenu Advanced_operation 1
        option None
        option Sqrt domain mix
        option Exp domain mix
        option Vector morph
        option Logistic chaos
        option Rectify and mix
        option Pseudo phase-vocoder
        option Random scatter
    
    comment === Parameters ===
    positive Modulation_depth 1.0
    positive Nonlinear_intensity 0.5
    positive Output_scaling 1.0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset > 1
    # Reset to defaults
    modulation_operation = 1
    nonlinear_operation = 1
    advanced_operation = 1
    output_scaling = 1.0
    operation = 1
    
    if preset = 2
        # Clean Add
        operation = 1
        presetName$ = "Add"
    elsif preset = 3
        # Clean Multiply (Ring Mod)
        operation = 3
        presetName$ = "RingMod"
    elsif preset = 4
        # Tremolo
        modulation_operation = 9
        modulation_depth = 0.5
        presetName$ = "Tremolo"
    elsif preset = 5
        # Crunch Mod
        modulation_operation = 7
        modulation_depth = 2.0
        presetName$ = "Crunch"
    elsif preset = 6
        # FM Synthesis
        modulation_operation = 4
        modulation_depth = 2.0
        presetName$ = "FM"
    elsif preset = 7
        # Double FM
        modulation_operation = 6
        modulation_depth = 1.5
        presetName$ = "DoubleFM"
    elsif preset = 8
        # Wavefold
        nonlinear_operation = 4
        nonlinear_intensity = 0.8
        presetName$ = "Wavefold"
    elsif preset = 9
        # Bitcrush
        nonlinear_operation = 6
        nonlinear_intensity = 0.5
        presetName$ = "Bitcrush"
    elsif preset = 10
        # Frequency Shifter
        nonlinear_operation = 2
        nonlinear_intensity = 1.2
        presetName$ = "FreqShift"
    elsif preset = 11
        # Hard Sync
        nonlinear_operation = 5
        nonlinear_intensity = 0.9
        presetName$ = "HardSync"
    elsif preset = 12
        # Chaotic Mix
        advanced_operation = 5
        nonlinear_intensity = 0.5
        presetName$ = "Chaos"
    elsif preset = 13
        # Spectral Blur
        nonlinear_operation = 8
        nonlinear_intensity = 0.8
        presetName$ = "SpectralBlur"
    elsif preset = 14
        # Phase Vocoder
        advanced_operation = 7
        nonlinear_intensity = 0.5
        presetName$ = "PhaseVoc"
    elsif preset = 15
        # Granular Scatter
        advanced_operation = 8
        nonlinear_intensity = 0.6
        presetName$ = "Scatter"
    elsif preset = 16
        # Sqrt Domain
        advanced_operation = 2
        nonlinear_intensity = 0.5
        presetName$ = "SqrtDomain"
    elsif preset = 17
        # Vector Morph
        advanced_operation = 4
        nonlinear_intensity = 0.5
        presetName$ = "VectorMorph"
    elsif preset = 18
        # Rectify
        advanced_operation = 6
        nonlinear_intensity = 0.0
        presetName$ = "Rectify"
    endif
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly 2 Sound objects."
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

# Check sample rates match
if sr1 <> sr2
    exitScript: "Sample rates must match (S1: " + string$(sr1) + " Hz, S2: " + string$(sr2) + " Hz)"
endif

min_dur = min(dur1, dur2)

# === Info ===
writeInfoLine: "=== Math Operations ==="
appendInfoLine: "Sound 1: ", name1$, " (", fixed$(dur1, 2), " s)"
appendInfoLine: "Sound 2: ", name2$, " (", fixed$(dur2, 2), " s)"
appendInfoLine: "Using duration: ", fixed$(min_dur, 2), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# === Extract Equal Parts ===
selectObject: sound1
Extract part: 0, min_dur, "rectangular", 1, "no"
sound1_part = selected("Sound")

selectObject: sound2
Extract part: 0, min_dur, "rectangular", 1, "no"
sound2_part = selected("Sound")

# === Create Result ===
selectObject: sound1_part
Copy: name1$ + "_" + presetName$ + "_" + name2$
result = selected("Sound")

# Build object reference string
s2_str$ = string$(sound2_part)

# === CORE MATH PROCESSING ===
# Priority: Advanced > Nonlinear > Modulation > Basic

selectObject: result

if advanced_operation > 1
    # === ADVANCED TRANSFORMS ===
    depth_str$ = string$(nonlinear_intensity)
    
    if advanced_operation = 2
        # Sqrt domain mix
        appendInfoLine: "Applying: Sqrt domain mix"
        Formula: ~ sqrt(abs(self) + 1e-10) * sqrt(abs(object[sound2_part]) + 1e-10) * 10
    elsif advanced_operation = 3
        # Exp domain mix
        appendInfoLine: "Applying: Exp domain mix"
        Formula: ~ exp(ln(abs(self) + 1e-10) + ln(abs(object[sound2_part]) + 1e-10)) * 0.1
    elsif advanced_operation = 4
        # Vector morph
        appendInfoLine: "Applying: Vector morph (depth=", nonlinear_intensity, ")"
        Formula: "self * (1 - " + depth_str$ + ") + object[" + s2_str$ + "] * " + depth_str$
    elsif advanced_operation = 5
        # Logistic chaos
        appendInfoLine: "Applying: Logistic chaos"
        Formula: ~ (self + object[sound2_part]) * (3.5 - 3.5 * abs(self) * abs(object[sound2_part]))
    elsif advanced_operation = 6
        # Rectify & mix
        appendInfoLine: "Applying: Rectify & mix"
        Formula: ~ abs(self) - abs(object[sound2_part])
    elsif advanced_operation = 7
        # Phase vocoder sim
        appendInfoLine: "Applying: Pseudo phase-vocoder"
        Formula: ~ self * cos(object[sound2_part] * 50 * pi) + object[sound2_part] * sin(self * 50 * pi)
    elsif advanced_operation = 8
        # Random scatter
        appendInfoLine: "Applying: Random scatter"
        Formula: ~ (self + object[sound2_part]) * (0.8 + 0.4 * randomUniform(-1, 1))
    endif

elsif nonlinear_operation > 1
    # === NONLINEAR OPERATIONS ===
    intensity_str$ = string$(nonlinear_intensity)
    
    if nonlinear_operation = 2
        # Freq shifter sim
        appendInfoLine: "Applying: Freq shift sim"
        Formula: "self * cos(2 * pi * object[" + s2_str$ + "] * " + intensity_str$ + " * 100)"
    elsif nonlinear_operation = 3
        # AM depth control
        appendInfoLine: "Applying: AM depth control"
        Formula: "self * (1 + object[" + s2_str$ + "] * " + intensity_str$ + ")"
    elsif nonlinear_operation = 4
        # Wavefold
        appendInfoLine: "Applying: Wavefold"
        thresh = 0.5 + nonlinear_intensity
        thresh_str$ = string$(thresh)
        Formula: "if abs(self + object[" + s2_str$ + "]) > " + thresh_str$ + " then " + thresh_str$ + " * sign(self + object[" + s2_str$ + "]) - (self + object[" + s2_str$ + "] - " + thresh_str$ + " * sign(self + object[" + s2_str$ + "])) else self + object[" + s2_str$ + "] fi"
    elsif nonlinear_operation = 5
        # Hard sync sim
        appendInfoLine: "Applying: Hard sync sim"
        Formula: "if abs(object[" + s2_str$ + "]) > abs(self) * " + intensity_str$ + " then sign(object[" + s2_str$ + "]) * abs(self) else self * object[" + s2_str$ + "] fi"
    elsif nonlinear_operation = 6
        # Bitcrush
        appendInfoLine: "Applying: Bitcrush 8-bit"
        Formula: ~ round((self + object[sound2_part]) * 8) / 8
    elsif nonlinear_operation = 7
        # Vector crossfade
        appendInfoLine: "Applying: Vector crossfade"
        Formula: "self * (1 - " + intensity_str$ + " * abs(object[" + s2_str$ + "])) + object[" + s2_str$ + "] * " + intensity_str$
    elsif nonlinear_operation = 8
        # Soft normalize
        appendInfoLine: "Applying: Soft normalize mix"
        Formula: "(self + object[" + s2_str$ + "]) / (1 + " + intensity_str$ + " * (abs(self) + abs(object[" + s2_str$ + "])))"
    endif

elsif modulation_operation > 1
    # === MODULATION OPERATIONS ===
    mod_str$ = string$(modulation_depth)
    
    if modulation_operation = 2
        # AM sin
        appendInfoLine: "Applying: AM (sin)"
        Formula: "self * (0.5 + 0.5 * sin(object[" + s2_str$ + "] * pi * 10 * " + mod_str$ + "))"
    elsif modulation_operation = 3
        # AM cos
        appendInfoLine: "Applying: AM (cos)"
        Formula: "self * (0.5 + 0.5 * cos(object[" + s2_str$ + "] * pi * 10 * " + mod_str$ + "))"
    elsif modulation_operation = 4
        # FM 1
        appendInfoLine: "Applying: FM-like (sin)"
        Formula: "sin(self * pi * 5 * " + mod_str$ + ") * object[" + s2_str$ + "]"
    elsif modulation_operation = 5
        # FM 2
        appendInfoLine: "Applying: FM-like (cos)"
        Formula: "cos(self * pi * 5 * " + mod_str$ + ") * object[" + s2_str$ + "]"
    elsif modulation_operation = 6
        # Double FM
        appendInfoLine: "Applying: Double FM"
        Formula: "sin(self * pi * 5 * " + mod_str$ + ") * sin(object[" + s2_str$ + "] * pi * 5 * " + mod_str$ + ")"
    elsif modulation_operation = 7
        # Arctan (crunchy)
        appendInfoLine: "Applying: Soft clip (arctan)"
        Formula: "(2/pi) * arctan((self * object[" + s2_str$ + "]) * 10 * " + mod_str$ + ")"
    elsif modulation_operation = 8
        # Power mod
        appendInfoLine: "Applying: Power mod"
        Formula: "if abs(object[" + s2_str$ + "]) < 0.01 then self else sign(self) * (abs(self) ^ (1 + object[" + s2_str$ + "] * " + mod_str$ + ")) fi"
    elsif modulation_operation = 9
        # Tremolo
        appendInfoLine: "Applying: Tremolo"
        Formula: "self * (1 + object[" + s2_str$ + "] * " + mod_str$ + ")"
    endif

else
    # === BASIC OPERATIONS ===
    if operation = 1
        appendInfoLine: "Applying: Add"
        Formula: ~ self + object[sound2_part]
    elsif operation = 2
        appendInfoLine: "Applying: Subtract"
        Formula: ~ self - object[sound2_part]
    elsif operation = 3
        appendInfoLine: "Applying: Multiply (Ring Mod)"
        Formula: ~ self * object[sound2_part]
    elsif operation = 4
        appendInfoLine: "Applying: Divide"
        Formula: ~ self / (object[sound2_part] + 1e-10)
    elsif operation = 5
        appendInfoLine: "Applying: Average"
        Formula: ~ (self + object[sound2_part]) / 2
    elsif operation = 6
        appendInfoLine: "Applying: Minimum"
        Formula: ~ min(self, object[sound2_part])
    elsif operation = 7
        appendInfoLine: "Applying: Maximum"
        Formula: ~ max(self, object[sound2_part])
    elsif operation = 8
        appendInfoLine: "Applying: Absolute difference"
        Formula: ~ abs(self - object[sound2_part])
    elsif operation = 9
        appendInfoLine: "Applying: XOR-like"
        Formula: ~ if self * object[sound2_part] < 0 then -(abs(self) + abs(object[sound2_part])) / 2 else (abs(self) + abs(object[sound2_part])) / 2 fi
    endif
endif

# === POST PROCESSING ===
selectObject: result

if output_scaling <> 1.0
    scale_str$ = string$(output_scaling)
    Formula: "self * " + scale_str$
endif

if normalize_output
    Scale peak: 0.95
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Math Operations: " + name1$ + " ○ " + name2$ + " (" + presetName$ + ")"
    
    # Sound 1 waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: sound1_part
    Colour: "{0.5, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Sound 1"
    
    # Sound 2 waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: sound2_part
    Colour: "{0.5, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Sound 2"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.4, 3.4
    Select inner viewport: 0.6, 7.6, 2.5, 3.3
    selectObject: result
    Colour: "{0.7, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Operation diagram
    Select outer viewport: 0, 4, 3.6, 4.8
    Select inner viewport: 0.6, 3.8, 3.7, 4.7
    
    Axes: 0, 4, 0, 3
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 3
    
    Font size: 6
    
    # S1 box
    Paint rectangle: "{0.7, 0.85, 0.7}", 0.2, 1.0, 1.8, 2.5
    Colour: "Black"
    Text: 0.6, "centre", 2.15, "half", "S1"
    
    # S2 box
    Paint rectangle: "{0.7, 0.7, 0.85}", 0.2, 1.0, 0.5, 1.2
    Text: 0.6, "centre", 0.85, "half", "S2"
    
    # Operation box
    Paint rectangle: "{0.85, 0.75, 0.8}", 1.5, 2.5, 1.0, 2.0
    Text: 2.0, "centre", 1.5, "half", presetName$
    
    # Arrows
    Draw arrow: 1.0, 2.15, 1.5, 1.7
    Draw arrow: 1.0, 0.85, 1.5, 1.3
    Draw arrow: 2.5, 1.5, 3.0, 1.5
    
    # Result box
    Paint rectangle: "{0.8, 0.7, 0.75}", 3.0, 3.8, 1.0, 2.0
    Text: 3.4, "centre", 1.5, "half", "Out"
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 4, 8, 3.6, 4.8
    Select inner viewport: 4.4, 7.6, 3.7, 4.7
    
    Axes: 0, 4, 0, 5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 5
    
    Font size: 5
    Colour: "{0.4, 0.4, 0.4}"
    
    Text: 0.2, "left", 4.5, "half", "Mod depth: " + fixed$(modulation_depth, 2)
    Text: 0.2, "left", 3.7, "half", "Nonlinear: " + fixed$(nonlinear_intensity, 2)
    Text: 0.2, "left", 2.9, "half", "Output scale: " + fixed$(output_scaling, 2)
    Text: 0.2, "left", 2.1, "half", "Normalize: " + if normalize_output then "yes" else "no" fi
    Text: 0.2, "left", 1.3, "half", "Duration: " + fixed$(min_dur, 2) + " s"
    
    Colour: "Black"
    Draw inner box
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: sound1_part, sound2_part

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