# ============================================================
# Praat AudioTools - Math_Operations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Math Operations Between Two Sounds — combines two audio
#   files using mathematical operations. Includes basic math
#   (add, multiply/ring mod, etc.), modulation (AM, FM),
#   nonlinear processing (wavefold, bitcrush), and advanced
#   transforms (vector morph, chaos, phase vocoder sim).
#   Select exactly 2 Sound objects before running.
#
#   The two inputs must share the same sample rate. Different
#   durations are aligned at start and truncated to the shorter
#   length.
#
#   OPERATION PRIORITY ORDER:
#   The script applies ONE operation chosen by priority:
#     Advanced > Nonlinear > Modulation > Basic
#   If you select both a Nonlinear and a Modulation operation,
#   only Nonlinear runs (Modulation is silently ignored). To
#   use a Basic operation, leave the other three menus on
#   "None". Presets handle this automatically.
#
#   NAMING NOTES:
#   - "Bitcrush 8-bit" actually quantizes to 8 levels (~3 bits).
#     A true 8-bit crush would have 256 levels.
#   - "Logistic chaos" is not the recursive logistic map x_{n+1} =
#     r*x*(1-x). It is a product (s1+s2) * (3.5 - 3.5*|s1|*|s2|),
#     which produces audio-rate amplitude shaping but no
#     recursive iteration.
#   - "Hard sync sim" is an audio-effect pseudo-sync, not a
#     phase-reset oscillator-style hard sync.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. Same Formula expressions
#     for every operation. Same priority order. Same Scale peak.
#   - Form syntax modernized: all five optionmenus use colon.
#   - Pre-computed display strings (replaces v0.2 inline if/then/
#     else fi in parameter-panel Text — unreliable in Praat's
#     script-level expression context).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): operation diagram showing
#         S1 + S2 -> operation -> Out
#       Panel B (right, headline): parameter report listing
#         which menu's operation actually ran (so users see the
#         priority resolution)
#       Panel C: side-by-side input waveforms (S1 green, S2 blue,
#         half-width each)
#       Panel D: result waveform with L/R channels distinguished
#       Panel E: summary stats bar
#   - Header documents the priority order (Advanced > Nonlinear >
#     Modulation > Basic) so users understand why some menu
#     selections are silently ignored.
#   - Header documents the 8-level vs 8-bit naming, the
#     non-iterative "logistic chaos," and pseudo "hard sync"
#     so users understand what they are actually getting.
# Changelog v0.2:
#   - Fixed formula syntax (Formula: ~)
#   - Fixed undefined variable errors
#   - Added visualization
#   - Added info output
# ============================================================

form Math Operations Between Sounds v0.3
    comment Select exactly 2 Sound objects first
    
    comment === Preset ===
    optionmenu Preset: 1
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
    optionmenu Operation: 2
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
    optionmenu Modulation_operation: 1
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
    optionmenu Nonlinear_operation: 1
        option None
        option Freq shift sim
        option AM depth control
        option Wavefold
        option Hard sync sim
        option Bitcrush (8 levels, ~3-bit)
        option Vector crossfade
        option Soft normalize mix
    
    comment === Advanced ===
    optionmenu Advanced_operation: 1
        option None
        option Sqrt domain mix
        option Exp domain mix
        option Vector morph
        option Logistic-style (non-recursive)
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
    # Reset all menus to defaults
    modulation_operation = 1
    nonlinear_operation = 1
    advanced_operation = 1
    output_scaling = 1.0
    operation = 1
    
    if preset = 2
        operation = 1
        presetName$ = "Add"
    elsif preset = 3
        operation = 3
        presetName$ = "RingMod"
    elsif preset = 4
        modulation_operation = 9
        modulation_depth = 0.5
        presetName$ = "Tremolo"
    elsif preset = 5
        modulation_operation = 7
        modulation_depth = 2.0
        presetName$ = "Crunch"
    elsif preset = 6
        modulation_operation = 4
        modulation_depth = 2.0
        presetName$ = "FM"
    elsif preset = 7
        modulation_operation = 6
        modulation_depth = 1.5
        presetName$ = "DoubleFM"
    elsif preset = 8
        nonlinear_operation = 4
        nonlinear_intensity = 0.8
        presetName$ = "Wavefold"
    elsif preset = 9
        nonlinear_operation = 6
        nonlinear_intensity = 0.5
        presetName$ = "Bitcrush"
    elsif preset = 10
        nonlinear_operation = 2
        nonlinear_intensity = 1.2
        presetName$ = "FreqShift"
    elsif preset = 11
        nonlinear_operation = 5
        nonlinear_intensity = 0.9
        presetName$ = "HardSync"
    elsif preset = 12
        advanced_operation = 5
        nonlinear_intensity = 0.5
        presetName$ = "Chaos"
    elsif preset = 13
        nonlinear_operation = 8
        nonlinear_intensity = 0.8
        presetName$ = "SpectralBlur"
    elsif preset = 14
        advanced_operation = 7
        nonlinear_intensity = 0.5
        presetName$ = "PhaseVoc"
    elsif preset = 15
        advanced_operation = 8
        nonlinear_intensity = 0.6
        presetName$ = "Scatter"
    elsif preset = 16
        advanced_operation = 2
        nonlinear_intensity = 0.5
        presetName$ = "SqrtDomain"
    elsif preset = 17
        advanced_operation = 4
        nonlinear_intensity = 0.5
        presetName$ = "VectorMorph"
    elsif preset = 18
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
n_ch_1 = Get number of channels

selectObject: sound2
name2$ = selected$("Sound")
sr2 = Get sampling frequency
dur2 = Get total duration
n_ch_2 = Get number of channels

# Check sample rates match
if sr1 <> sr2
    exitScript: "Sample rates must match (S1: " + string$(sr1) + " Hz, S2: " + string$(sr2) + " Hz)"
endif

min_dur = min(dur1, dur2)

# === Info ===
writeInfoLine: "=== Math Operations v0.3 ==="
appendInfoLine: "Sound 1: ", name1$, " (", fixed$(dur1, 2), " s, ", n_ch_1, " ch)"
appendInfoLine: "Sound 2: ", name2$, " (", fixed$(dur2, 2), " s, ", n_ch_2, " ch)"
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
# Track which tier ran for visualization clarity
ranTier$ = "none"
ranLabel$ = "(no operation)"

selectObject: result

if advanced_operation > 1
    ranTier$ = "Advanced"
    depth_str$ = string$(nonlinear_intensity)
    
    if advanced_operation = 2
        ranLabel$ = "Sqrt domain mix"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ sqrt(abs(self) + 1e-10) * sqrt(abs(object[sound2_part]) + 1e-10) * 10
    elsif advanced_operation = 3
        ranLabel$ = "Exp domain mix"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ exp(ln(abs(self) + 1e-10) + ln(abs(object[sound2_part]) + 1e-10)) * 0.1
    elsif advanced_operation = 4
        ranLabel$ = "Vector morph (depth=" + fixed$(nonlinear_intensity, 2) + ")"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 - " + depth_str$ + ") + object[" + s2_str$ + "] * " + depth_str$
    elsif advanced_operation = 5
        ranLabel$ = "Logistic-style chaos (non-recursive)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ (self + object[sound2_part]) * (3.5 - 3.5 * abs(self) * abs(object[sound2_part]))
    elsif advanced_operation = 6
        ranLabel$ = "Rectify & mix"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ abs(self) - abs(object[sound2_part])
    elsif advanced_operation = 7
        ranLabel$ = "Pseudo phase-vocoder"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self * cos(object[sound2_part] * 50 * pi) + object[sound2_part] * sin(self * 50 * pi)
    elsif advanced_operation = 8
        ranLabel$ = "Random scatter"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ (self + object[sound2_part]) * (0.8 + 0.4 * randomUniform(-1, 1))
    endif

elsif nonlinear_operation > 1
    ranTier$ = "Nonlinear"
    intensity_str$ = string$(nonlinear_intensity)
    
    if nonlinear_operation = 2
        ranLabel$ = "Freq shift sim"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * cos(2 * pi * object[" + s2_str$ + "] * " + intensity_str$ + " * 100)"
    elsif nonlinear_operation = 3
        ranLabel$ = "AM depth control"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 + object[" + s2_str$ + "] * " + intensity_str$ + ")"
    elsif nonlinear_operation = 4
        ranLabel$ = "Wavefold"
        appendInfoLine: "Applying: ", ranLabel$
        thresh = 0.5 + nonlinear_intensity
        thresh_str$ = string$(thresh)
        Formula: "if abs(self + object[" + s2_str$ + "]) > " + thresh_str$ + " then " + thresh_str$ + " * sign(self + object[" + s2_str$ + "]) - (self + object[" + s2_str$ + "] - " + thresh_str$ + " * sign(self + object[" + s2_str$ + "])) else self + object[" + s2_str$ + "] fi"
    elsif nonlinear_operation = 5
        ranLabel$ = "Hard sync sim"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "if abs(object[" + s2_str$ + "]) > abs(self) * " + intensity_str$ + " then sign(object[" + s2_str$ + "]) * abs(self) else self * object[" + s2_str$ + "] fi"
    elsif nonlinear_operation = 6
        ranLabel$ = "Bitcrush (8 levels, ~3-bit)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ round((self + object[sound2_part]) * 8) / 8
    elsif nonlinear_operation = 7
        ranLabel$ = "Vector crossfade"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 - " + intensity_str$ + " * abs(object[" + s2_str$ + "])) + object[" + s2_str$ + "] * " + intensity_str$
    elsif nonlinear_operation = 8
        ranLabel$ = "Soft normalize mix"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "(self + object[" + s2_str$ + "]) / (1 + " + intensity_str$ + " * (abs(self) + abs(object[" + s2_str$ + "])))"
    endif

elsif modulation_operation > 1
    ranTier$ = "Modulation"
    mod_str$ = string$(modulation_depth)
    
    if modulation_operation = 2
        ranLabel$ = "AM (sin)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (0.5 + 0.5 * sin(object[" + s2_str$ + "] * pi * 10 * " + mod_str$ + "))"
    elsif modulation_operation = 3
        ranLabel$ = "AM (cos)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (0.5 + 0.5 * cos(object[" + s2_str$ + "] * pi * 10 * " + mod_str$ + "))"
    elsif modulation_operation = 4
        ranLabel$ = "FM-like (sin)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "sin(self * pi * 5 * " + mod_str$ + ") * object[" + s2_str$ + "]"
    elsif modulation_operation = 5
        ranLabel$ = "FM-like (cos)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "cos(self * pi * 5 * " + mod_str$ + ") * object[" + s2_str$ + "]"
    elsif modulation_operation = 6
        ranLabel$ = "Double FM"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "sin(self * pi * 5 * " + mod_str$ + ") * sin(object[" + s2_str$ + "] * pi * 5 * " + mod_str$ + ")"
    elsif modulation_operation = 7
        ranLabel$ = "Soft clip (arctan)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "(2/pi) * arctan((self * object[" + s2_str$ + "]) * 10 * " + mod_str$ + ")"
    elsif modulation_operation = 8
        ranLabel$ = "Power mod"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "if abs(object[" + s2_str$ + "]) < 0.01 then self else sign(self) * (abs(self) ^ (1 + object[" + s2_str$ + "] * " + mod_str$ + ")) fi"
    elsif modulation_operation = 9
        ranLabel$ = "Tremolo"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 + object[" + s2_str$ + "] * " + mod_str$ + ")"
    endif

else
    ranTier$ = "Basic"
    if operation = 1
        ranLabel$ = "Add"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self + object[sound2_part]
    elsif operation = 2
        ranLabel$ = "Subtract"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self - object[sound2_part]
    elsif operation = 3
        ranLabel$ = "Multiply (Ring Mod)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self * object[sound2_part]
    elsif operation = 4
        ranLabel$ = "Divide"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self / (object[sound2_part] + 1e-10)
    elsif operation = 5
        ranLabel$ = "Average"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ (self + object[sound2_part]) / 2
    elsif operation = 6
        ranLabel$ = "Minimum"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ min(self, object[sound2_part])
    elsif operation = 7
        ranLabel$ = "Maximum"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ max(self, object[sound2_part])
    elsif operation = 8
        ranLabel$ = "Absolute difference"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ abs(self - object[sound2_part])
    elsif operation = 9
        ranLabel$ = "XOR-like (sign mixing)"
        appendInfoLine: "Applying: ", ranLabel$
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

# Pre-compute the normalize-status string (replaces v0.2's
# inline if/then/else fi in Text — unreliable in script-level
# expression context).
if normalize_output
    normStr$ = "yes (peak 0.95)"
else
    normStr$ = "no"
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
n_ch_result = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##MATH OPERATIONS BETWEEN SOUNDS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... name1$ + "  o  " + name2$
        ... + "  |  " + presetName$
        ... + "  |  Tier: " + ranTier$
        ... + "  |  Op: " + ranLabel$
        ... + "  |  Duration: " + fixed$(min_dur, 2) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: OPERATION DIAGRAM  (left, headline)
    # S1 + S2 -> [operation] -> Out
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, 4, 0, 4
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 4, 0, 4
    
    # Sound 1 box (top left)
    Paint rectangle: "{0.65, 0.85, 0.65}", 0.30, 1.30, 2.50, 3.30
    Colour: "Black"
    Font size: 9
    Text: 0.80, "centre", 2.95, "half", "Sound 1"
    Font size: 6
    Colour: "{0.20, 0.40, 0.20}"
    Text: 0.80, "centre", 2.78, "half", name1$
    Text: 0.80, "centre", 2.65, "half", "(" + fixed$(dur1, 2) + " s, " + string$(n_ch_1) + " ch)"
    
    # Sound 2 box (bottom left)
    Paint rectangle: "{0.65, 0.65, 0.85}", 0.30, 1.30, 0.70, 1.50
    Colour: "Black"
    Font size: 9
    Text: 0.80, "centre", 1.20, "half", "Sound 2"
    Font size: 6
    Colour: "{0.15, 0.20, 0.45}"
    Text: 0.80, "centre", 1.03, "half", name2$
    Text: 0.80, "centre", 0.88, "half", "(" + fixed$(dur2, 2) + " s, " + string$(n_ch_2) + " ch)"
    
    # Operation box (center)
    Paint rectangle: "{0.85, 0.75, 0.80}", 1.65, 2.65, 1.50, 2.50
    Colour: "Black"
    Font size: 8
    Text: 2.15, "centre", 2.20, "half", presetName$
    Font size: 6
    Colour: "{0.45, 0.20, 0.30}"
    Text: 2.15, "centre", 2.05, "half", "[" + ranTier$ + "]"
    Font size: 5
    Text: 2.15, "centre", 1.85, "half", ranLabel$
    
    # Result box (right)
    Paint rectangle: "{0.85, 0.65, 0.55}", 3.00, 4.00, 1.50, 2.50
    Colour: "Black"
    Font size: 9
    Text: 3.50, "centre", 2.20, "half", "Result"
    Font size: 6
    Colour: "{0.40, 0.20, 0.10}"
    Text: 3.50, "centre", 2.05, "half", "(" + fixed$(min_dur, 2) + " s)"
    Text: 3.50, "centre", 1.90, "half", "peak " + fixed$(finalPeak, 3)
    
    # Arrows
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1.5
    Draw arrow: 1.30, 2.85, 1.65, 2.20
    Draw arrow: 1.30, 1.15, 1.65, 1.80
    Draw arrow: 2.65, 2.00, 3.00, 2.00
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    # Section: Operation
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Operation tier:"
    
    Font size: 11
    if ranTier$ = "Advanced"
        Colour: "{0.78, 0.30, 0.40}"
    elsif ranTier$ = "Nonlinear"
        Colour: "{0.78, 0.50, 0.30}"
    elsif ranTier$ = "Modulation"
        Colour: "{0.30, 0.55, 0.78}"
    else
        Colour: "{0.30, 0.55, 0.30}"
    endif
    Text: 0.10, "left", 0.84, "half", ranTier$
    
    Font size: 8
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.10, "left", 0.76, "half", ranLabel$
    
    # Section: Parameters (relevant to this tier)
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.65, "half", "Parameters:"
    
    Font size: 10
    Colour: "{0.30, 0.45, 0.78}"
    if ranTier$ = "Modulation"
        Text: 0.10, "left", 0.57, "half", "Mod depth:    " + fixed$(modulation_depth, 2)
    elsif ranTier$ = "Nonlinear" or ranTier$ = "Advanced"
        Text: 0.10, "left", 0.57, "half", "Intensity:    " + fixed$(nonlinear_intensity, 2)
    else
        Text: 0.10, "left", 0.57, "half", "(no tier-specific param)"
    endif
    Text: 0.10, "left", 0.49, "half", "Output scale: " + fixed$(output_scaling, 2)
    Text: 0.10, "left", 0.41, "half", "Normalize:    " + normStr$
    
    # Section: Duration / Channels
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.30, "half", "Duration alignment:"
    
    Font size: 8
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.22, "half", "S1: " + fixed$(dur1, 2) + " s, " + string$(n_ch_1) + " ch"
    Text: 0.10, "left", 0.14, "half", "S2: " + fixed$(dur2, 2) + " s, " + string$(n_ch_2) + " ch"
    Font size: 7
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0.10, "left", 0.05, "half", "Used: min(S1, S2) = " + fixed$(min_dur, 2) + " s"
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Operation diagram"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: INPUT WAVEFORMS  (S1 left half, S2 right half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 4.68, 5.55
    Select inner viewport: 0.55, 3.85, 4.75, 5.48
    
    selectObject: sound1_part
    s1Peak = Get absolute extremum: 0, 0, "None"
    if s1Peak < 0.001
        s1Peak = 0.001
    endif
    s1Amp = s1Peak * 1.15
    
    Axes: 0, min_dur, -s1Amp, s1Amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, min_dur, -s1Amp, s1Amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, min_dur, 0
    
    selectObject: sound1_part
    Colour: "{0.30, 0.65, 0.30}"
    Line width: 1
    Draw: 0, 0, -s1Amp, s1Amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Sound 1 (green)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 4, 8, 4.68, 5.55
    Select inner viewport: 4.20, 7.65, 4.75, 5.48
    
    selectObject: sound2_part
    s2Peak = Get absolute extremum: 0, 0, "None"
    if s2Peak < 0.001
        s2Peak = 0.001
    endif
    s2Amp = s2Peak * 1.15
    
    Axes: 0, min_dur, -s2Amp, s2Amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, min_dur, -s2Amp, s2Amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, min_dur, 0
    
    selectObject: sound2_part
    Colour: "{0.30, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -s2Amp, s2Amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Sound 2 (blue)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: RESULT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
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
    if n_ch_result = 1
        Colour: "{0.78, 0.40, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if n_ch_result >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if n_ch_result > 1
        Text top: "no", "Result  (blue=L  orange=R)"
    else
        Text top: "no", "Result (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  S1: " + name1$ + "  o  S2: " + name2$
        ... + "  |  Tier: " + ranTier$
        ... + "  |  Op: " + ranLabel$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Mod depth: " + fixed$(modulation_depth, 2)
        ... + "  |  Intensity: " + fixed$(nonlinear_intensity, 2)
        ... + "  |  Out scale: " + fixed$(output_scaling, 2)
        ... + "  |  Normalize: " + normStr$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Cleanup ===
removeObject: sound1_part, sound2_part

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Tier: ", ranTier$, "  |  Op: ", ranLabel$
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s, peak ", fixed$(finalPeak, 4)

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
