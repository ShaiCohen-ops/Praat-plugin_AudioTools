# ============================================================
# Praat AudioTools - Artificial_Room.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Artificial Room - physically-modeled convolution reverb.
#   Simulates room acoustics using real material absorption
#   coefficients, calculates RT60 per frequency band using
#   Eyring formula, generates synthetic impulse response with
#   early reflections and frequency-dependent decay tail.
#   Includes 20 acoustic materials and 4 room presets.
#
# Changelog v0.2:
#   - Added wet/dry mix control
#   - Fixed exit syntax
#   - Fixed procedure call syntax
#   - Fixed name-based object references
#   - Added visualization (RT60 bars, IR waveform)
#   - Option to keep or remove IR
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputID = selected("Sound")
selectObject: inputID
inputName$ = selected$("Sound")
fs = Get sampling frequency
inputDur = Get total duration

# ==============================================================================
# 1) Materials and absorption data
# ==============================================================================

materials$[1] = "BrickPainted"
materials$[2] = "Concrete"
materials$[3] = "WoodFloor"
materials$[4] = "CarpetConcrete"
materials$[5] = "CurtainLight"
materials$[6] = "CurtainHeavy"
materials$[7] = "GypsumBoard"
materials$[8] = "GlassWindow"
materials$[9] = "AcousticFoam25mm"
materials$[10] = "AcousticFoam50mm"
materials$[11] = "Audience"
materials$[12] = "WoodPanel"
materials$[13] = "PlasterWall"
materials$[14] = "PlywoodPanel"
materials$[15] = "MineralWool50mm"
materials$[16] = "MineralWool100mm"
materials$[17] = "CarpetOnFelt"
materials$[18] = "Linoleum"
materials$[19] = "OpenWindow"
materials$[20] = "AcousticCeilingTile"

# Absorption coefficients per octave band
# 125 Hz
alpha125[1] = 0.01
alpha125[2] = 0.01
alpha125[3] = 0.15
alpha125[4] = 0.08
alpha125[5] = 0.05
alpha125[6] = 0.14
alpha125[7] = 0.10
alpha125[8] = 0.35
alpha125[9] = 0.15
alpha125[10] = 0.30
alpha125[11] = 0.30
alpha125[12] = 0.15
alpha125[13] = 0.02
alpha125[14] = 0.10
alpha125[15] = 0.25
alpha125[16] = 0.45
alpha125[17] = 0.10
alpha125[18] = 0.02
alpha125[19] = 1.00
alpha125[20] = 0.70

# 250 Hz
alpha250[1] = 0.01
alpha250[2] = 0.01
alpha250[3] = 0.11
alpha250[4] = 0.24
alpha250[5] = 0.15
alpha250[6] = 0.35
alpha250[7] = 0.08
alpha250[8] = 0.25
alpha250[9] = 0.40
alpha250[10] = 0.60
alpha250[11] = 0.45
alpha250[12] = 0.10
alpha250[13] = 0.02
alpha250[14] = 0.08
alpha250[15] = 0.55
alpha250[16] = 0.80
alpha250[17] = 0.35
alpha250[18] = 0.03
alpha250[19] = 1.00
alpha250[20] = 0.75

# 500 Hz
alpha500[1] = 0.02
alpha500[2] = 0.02
alpha500[3] = 0.10
alpha500[4] = 0.57
alpha500[5] = 0.35
alpha500[6] = 0.55
alpha500[7] = 0.05
alpha500[8] = 0.18
alpha500[9] = 0.70
alpha500[10] = 0.90
alpha500[11] = 0.55
alpha500[12] = 0.08
alpha500[13] = 0.03
alpha500[14] = 0.06
alpha500[15] = 0.85
alpha500[16] = 0.95
alpha500[17] = 0.55
alpha500[18] = 0.04
alpha500[19] = 1.00
alpha500[20] = 0.85

# 1000 Hz
alpha1000[1] = 0.02
alpha1000[2] = 0.02
alpha1000[3] = 0.07
alpha1000[4] = 0.69
alpha1000[5] = 0.55
alpha1000[6] = 0.72
alpha1000[7] = 0.03
alpha1000[8] = 0.12
alpha1000[9] = 0.85
alpha1000[10] = 0.95
alpha1000[11] = 0.60
alpha1000[12] = 0.07
alpha1000[13] = 0.03
alpha1000[14] = 0.05
alpha1000[15] = 0.95
alpha1000[16] = 0.95
alpha1000[17] = 0.65
alpha1000[18] = 0.05
alpha1000[19] = 1.00
alpha1000[20] = 0.90

# 2000 Hz
alpha2000[1] = 0.02
alpha2000[2] = 0.02
alpha2000[3] = 0.06
alpha2000[4] = 0.71
alpha2000[5] = 0.60
alpha2000[6] = 0.70
alpha2000[7] = 0.03
alpha2000[8] = 0.07
alpha2000[9] = 0.90
alpha2000[10] = 0.95
alpha2000[11] = 0.60
alpha2000[12] = 0.06
alpha2000[13] = 0.03
alpha2000[14] = 0.05
alpha2000[15] = 0.95
alpha2000[16] = 0.95
alpha2000[17] = 0.70
alpha2000[18] = 0.05
alpha2000[19] = 1.00
alpha2000[20] = 0.90

# 4000 Hz
alpha4000[1] = 0.02
alpha4000[2] = 0.02
alpha4000[3] = 0.07
alpha4000[4] = 0.73
alpha4000[5] = 0.55
alpha4000[6] = 0.65
alpha4000[7] = 0.03
alpha4000[8] = 0.05
alpha4000[9] = 0.90
alpha4000[10] = 0.90
alpha4000[11] = 0.55
alpha4000[12] = 0.07
alpha4000[13] = 0.03
alpha4000[14] = 0.05
alpha4000[15] = 0.90
alpha4000[16] = 0.90
alpha4000[17] = 0.75
alpha4000[18] = 0.05
alpha4000[19] = 1.00
alpha4000[20] = 0.85

# Octave band centers and edges
sqrtTwo = sqrt(2)

cen[1] = 125
low[1] = 125 / sqrtTwo
high[1] = 125 * sqrtTwo

cen[2] = 250
low[2] = 250 / sqrtTwo
high[2] = 250 * sqrtTwo

cen[3] = 500
low[3] = 500 / sqrtTwo
high[3] = 500 * sqrtTwo

cen[4] = 1000
low[4] = 1000 / sqrtTwo
high[4] = 1000 * sqrtTwo

cen[5] = 2000
low[5] = 2000 / sqrtTwo
high[5] = 2000 * sqrtTwo

cen[6] = 4000
low[6] = 4000 / sqrtTwo
high[6] = 4000 * sqrtTwo

# ==============================================================================
# 2) User Interface
# ==============================================================================

form Artificial Room Reverb
    comment Select a Sound object first
    
    comment === Room Preset ===
    choice Room_preset 1
        option SmallBooth (very dry)
        option Office (medium)
        option Classroom (larger)
        option LiveRoom (wood floor)
        option Custom (use settings below)
    
    comment === Custom Dimensions (only if Custom) ===
    positive Custom_length_m 5.0
    positive Custom_width_m 4.0
    positive Custom_height_m 2.8
    
    comment === Custom Materials (only if Custom) ===
    optionmenu Floor_material 4
        option BrickPainted
        option Concrete
        option WoodFloor
        option CarpetConcrete
        option CurtainLight
        option CurtainHeavy
        option GypsumBoard
        option GlassWindow
        option AcousticFoam25mm
        option AcousticFoam50mm
        option Audience
        option WoodPanel
        option PlasterWall
        option PlywoodPanel
        option MineralWool50mm
        option MineralWool100mm
        option CarpetOnFelt
        option Linoleum
        option OpenWindow
        option AcousticCeilingTile
    optionmenu Ceiling_material 20
        option BrickPainted
        option Concrete
        option WoodFloor
        option CarpetConcrete
        option CurtainLight
        option CurtainHeavy
        option GypsumBoard
        option GlassWindow
        option AcousticFoam25mm
        option AcousticFoam50mm
        option Audience
        option WoodPanel
        option PlasterWall
        option PlywoodPanel
        option MineralWool50mm
        option MineralWool100mm
        option CarpetOnFelt
        option Linoleum
        option OpenWindow
        option AcousticCeilingTile
    optionmenu Wall_material 7
        option BrickPainted
        option Concrete
        option WoodFloor
        option CarpetConcrete
        option CurtainLight
        option CurtainHeavy
        option GypsumBoard
        option GlassWindow
        option AcousticFoam25mm
        option AcousticFoam50mm
        option Audience
        option WoodPanel
        option PlasterWall
        option PlywoodPanel
        option MineralWool50mm
        option MineralWool100mm
        option CarpetOnFelt
        option Linoleum
        option OpenWindow
        option AcousticCeilingTile
    positive Audience_area_m2 0.1
    
    comment === IR Settings ===
    positive IR_predelay_ms 12.0
    real IR_early_gain_dB -6.0
    positive IR_length_factor 2.0
    natural Early_reflections_count 8
    
    comment === Mix Control ===
    real Wet_dry_percent 70
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Keep_IR 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# ==============================================================================
# 3) Apply Room Presets
# ==============================================================================

if room_preset = 1
    # SmallBooth
    roomL = 2.2
    roomW = 1.6
    roomH = 2.2
    mFloor$ = "CarpetConcrete"
    cFloor = 1.0
    mCeil$ = "MineralWool50mm"
    cCeil = 0.7
    mW1$ = "MineralWool50mm"
    cW1 = 0.6
    mW2$ = "MineralWool50mm"
    cW2 = 0.6
    mW3$ = "MineralWool50mm"
    cW3 = 0.6
    mW4$ = "MineralWool50mm"
    cW4 = 0.6
    audience_m2 = 0.0
    presetName$ = "SmallBooth"
elsif room_preset = 2
    # Office
    roomL = 4.5
    roomW = 3.5
    roomH = 2.7
    mFloor$ = "CarpetOnFelt"
    cFloor = 1.0
    mCeil$ = "AcousticCeilingTile"
    cCeil = 1.0
    mW1$ = "GypsumBoard"
    cW1 = 0.9
    mW2$ = "GypsumBoard"
    cW2 = 0.9
    mW3$ = "GlassWindow"
    cW3 = 0.3
    mW4$ = "CurtainLight"
    cW4 = 0.6
    audience_m2 = 1.5
    presetName$ = "Office"
elsif room_preset = 3
    # Classroom
    roomL = 8.0
    roomW = 6.0
    roomH = 3.2
    mFloor$ = "Linoleum"
    cFloor = 1.0
    mCeil$ = "AcousticCeilingTile"
    cCeil = 1.0
    mW1$ = "GypsumBoard"
    cW1 = 1.0
    mW2$ = "GypsumBoard"
    cW2 = 1.0
    mW3$ = "GypsumBoard"
    cW3 = 1.0
    mW4$ = "GypsumBoard"
    cW4 = 1.0
    audience_m2 = 8.0
    presetName$ = "Classroom"
elsif room_preset = 4
    # LiveRoom
    roomL = 7.0
    roomW = 5.0
    roomH = 3.0
    mFloor$ = "WoodFloor"
    cFloor = 1.0
    mCeil$ = "GypsumBoard"
    cCeil = 1.0
    mW1$ = "GypsumBoard"
    cW1 = 1.0
    mW2$ = "GypsumBoard"
    cW2 = 1.0
    mW3$ = "CurtainHeavy"
    cW3 = 0.5
    mW4$ = "MineralWool50mm"
    cW4 = 0.4
    audience_m2 = 0.0
    presetName$ = "LiveRoom"
else
    # Custom
    roomL = custom_length_m
    roomW = custom_width_m
    roomH = custom_height_m
    mFloor$ = materials$[floor_material]
    cFloor = 1.0
    mCeil$ = materials$[ceiling_material]
    cCeil = 1.0
    mW1$ = materials$[wall_material]
    cW1 = 1.0
    mW2$ = materials$[wall_material]
    cW2 = 1.0
    mW3$ = materials$[wall_material]
    cW3 = 1.0
    mW4$ = materials$[wall_material]
    cW4 = 1.0
    audience_m2 = audience_area_m2
    presetName$ = "Custom"
endif

# ==============================================================================
# 4) Calculate Room Geometry
# ==============================================================================

sfloor = roomL * roomW
sceiling = sfloor
sw1 = roomL * roomH
sw2 = roomL * roomH
sw3 = roomW * roomH
sw4 = roomW * roomH
stotal = sfloor + sceiling + sw1 + sw2 + sw3 + sw4
v = roomL * roomW * roomH

# ==============================================================================
# 5) Find Material Indices
# ==============================================================================

procedure findMaterialIndex: .mat$
    .result = 1
    for .jj from 1 to 20
        if materials$[.jj] = .mat$
            .result = .jj
        endif
    endfor
endproc

@findMaterialIndex: mFloor$
iFloor = findMaterialIndex.result

@findMaterialIndex: mCeil$
iCeil = findMaterialIndex.result

@findMaterialIndex: mW1$
iW1 = findMaterialIndex.result

@findMaterialIndex: mW2$
iW2 = findMaterialIndex.result

@findMaterialIndex: mW3$
iW3 = findMaterialIndex.result

@findMaterialIndex: mW4$
iW4 = findMaterialIndex.result

# ==============================================================================
# 6) Calculate RT60 per Band (Eyring Formula)
# ==============================================================================

procedure calculateRT60: .band
    # Get alpha values based on band
    if .band = 1
        .aF = alpha125[iFloor]
        .aC = alpha125[iCeil]
        .a1 = alpha125[iW1]
        .a2 = alpha125[iW2]
        .a3 = alpha125[iW3]
        .a4 = alpha125[iW4]
        .aAud = alpha125[11]
    elsif .band = 2
        .aF = alpha250[iFloor]
        .aC = alpha250[iCeil]
        .a1 = alpha250[iW1]
        .a2 = alpha250[iW2]
        .a3 = alpha250[iW3]
        .a4 = alpha250[iW4]
        .aAud = alpha250[11]
    elsif .band = 3
        .aF = alpha500[iFloor]
        .aC = alpha500[iCeil]
        .a1 = alpha500[iW1]
        .a2 = alpha500[iW2]
        .a3 = alpha500[iW3]
        .a4 = alpha500[iW4]
        .aAud = alpha500[11]
    elsif .band = 4
        .aF = alpha1000[iFloor]
        .aC = alpha1000[iCeil]
        .a1 = alpha1000[iW1]
        .a2 = alpha1000[iW2]
        .a3 = alpha1000[iW3]
        .a4 = alpha1000[iW4]
        .aAud = alpha1000[11]
    elsif .band = 5
        .aF = alpha2000[iFloor]
        .aC = alpha2000[iCeil]
        .a1 = alpha2000[iW1]
        .a2 = alpha2000[iW2]
        .a3 = alpha2000[iW3]
        .a4 = alpha2000[iW4]
        .aAud = alpha2000[11]
    else
        .aF = alpha4000[iFloor]
        .aC = alpha4000[iCeil]
        .a1 = alpha4000[iW1]
        .a2 = alpha4000[iW2]
        .a3 = alpha4000[iW3]
        .a4 = alpha4000[iW4]
        .aAud = alpha4000[11]
    endif
    
    # Apply coverage factors
    .aF = .aF * cFloor
    .aC = .aC * cCeil
    .a1 = .a1 * cW1
    .a2 = .a2 * cW2
    .a3 = .a3 * cW3
    .a4 = .a4 * cW4
    .aAud = .aAud * audience_m2
    
    # Total absorption
    .absArea = .aF * sfloor + .aC * sceiling + .a1 * sw1 + .a2 * sw2 + .a3 * sw3 + .a4 * sw4 + .aAud
    .alphaBar = .absArea / stotal
    
    if .alphaBar > 0.98
        .alphaBar = 0.98
    endif
    
    # Eyring formula: RT60 = 0.161 * V / (-S * ln(1 - alpha))
    .rt60 = 0.161 * v / (stotal * (-ln(1 - .alphaBar)))
    
    # Clamp
    if .rt60 < 0.12
        .rt60 = 0.12
    elsif .rt60 > 5.0
        .rt60 = 5.0
    endif
    
    result_rt60 = .rt60
endproc

# Calculate for all bands
@calculateRT60: 1
t60_1 = result_rt60

@calculateRT60: 2
t60_2 = result_rt60

@calculateRT60: 3
t60_3 = result_rt60

@calculateRT60: 4
t60_4 = result_rt60

@calculateRT60: 5
t60_5 = result_rt60

@calculateRT60: 6
t60_6 = result_rt60

# Store in array for convenience
t60[1] = t60_1
t60[2] = t60_2
t60[3] = t60_3
t60[4] = t60_4
t60[5] = t60_5
t60[6] = t60_6

# Find max RT60 for IR length
maxT = t60_1
for b from 2 to 6
    if t60[b] > maxT
        maxT = t60[b]
    endif
endfor

# IR length
if iR_length_factor < 0.8
    iR_length_factor = 0.8
elsif iR_length_factor > 4.0
    iR_length_factor = 4.0
endif

ir_length = maxT * iR_length_factor
pre_delay = iR_predelay_ms / 1000

# ==============================================================================
# 7) Info Output
# ==============================================================================

writeInfoLine: "=== Artificial Room Reverb ==="
appendInfoLine: "Source: ", inputName$, " (", fixed$(inputDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Room: ", fixed$(roomL, 1), " x ", fixed$(roomW, 1), " x ", fixed$(roomH, 1), " m"
appendInfoLine: "Volume: ", fixed$(v, 1), " m3"
appendInfoLine: "Total surface: ", fixed$(stotal, 1), " m2"
appendInfoLine: ""
appendInfoLine: "Materials:"
appendInfoLine: "  Floor: ", mFloor$
appendInfoLine: "  Ceiling: ", mCeil$
appendInfoLine: "  Walls: ", mW1$
appendInfoLine: ""
appendInfoLine: "RT60 (s):"
appendInfoLine: "  125 Hz:  ", fixed$(t60_1, 3)
appendInfoLine: "  250 Hz:  ", fixed$(t60_2, 3)
appendInfoLine: "  500 Hz:  ", fixed$(t60_3, 3)
appendInfoLine: "  1000 Hz: ", fixed$(t60_4, 3)
appendInfoLine: "  2000 Hz: ", fixed$(t60_5, 3)
appendInfoLine: "  4000 Hz: ", fixed$(t60_6, 3)
appendInfoLine: ""
appendInfoLine: "IR length: ", fixed$(ir_length, 2), " s"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# ==============================================================================
# 8) Build Synthetic IR
# ==============================================================================

appendInfoLine: "Building impulse response..."

Create Sound from formula: "IR_base", 1, 0, ir_length, fs, "0"
irBase = selected("Sound")

# Early reflections (Hann-windowed pulses)
nTaps = early_reflections_count
pulse_dur = 0.0007

for k from 1 to nTaps
    t0 = pre_delay + randomUniform(0.004, 0.050)
    gain_db = iR_early_gain_dB - ((k - 1) * 2.5)
    g = 10^(gain_db / 20) * randomUniform(0.9, 1.1)
    
    t0_str$ = string$(t0)
    t0_plus_str$ = string$(t0 + pulse_dur)
    g_str$ = string$(g)
    dur_str$ = string$(pulse_dur)
    pi2_str$ = string$(2 * pi)
    
    expr$ = "if x >= " + t0_str$ + " and x <= " + t0_plus_str$ + " then " + g_str$ + " * 0.5 * (1 - cos(" + pi2_str$ + " * (x - " + t0_str$ + ") / " + dur_str$ + ")) else 0 fi"
    
    Create Sound from formula: "IR_tap", 1, 0, ir_length, fs, expr$
    tapSound = selected("Sound")
    
    # Add to base
    tap_str$ = string$(tapSound)
    selectObject: irBase
    Formula: "self + object[" + tap_str$ + "]"
    
    removeObject: tapSound
endfor

# Late reverb (filtered noise with exponential decay per band)
for b from 1 to 6
    tau = t60[b] / 6
    tau_str$ = string$(tau)
    
    Create Sound from formula: "IR_noise", 1, 0, ir_length, fs, "randomGauss(0, 1) * exp(-x / " + tau_str$ + ")"
    noiseSound = selected("Sound")
    
    # Filter to band
    Filter (pass Hann band): low[b], high[b], 100
    filteredNoise = selected("Sound")
    
    # Attenuate high frequencies
    if cen[b] >= 2000
        fac_str$ = string$(10^(-0.75 / 20))
        Formula: "self * " + fac_str$
    endif
    
    # Add to base
    filt_str$ = string$(filteredNoise)
    selectObject: irBase
    Formula: "self + object[" + filt_str$ + "]"
    
    removeObject: noiseSound, filteredNoise
endfor

selectObject: irBase
Scale peak: 0.6
Rename: "IR_" + presetName$
irFinal = selected("Sound")

# ==============================================================================
# 9) Convolve and Mix Wet/Dry
# ==============================================================================

appendInfoLine: "Convolving..."

selectObject: inputID, irFinal
Convolve: "sum", "zero"
wetSound = selected("Sound")

# Trim to original length (convolution extends duration)
selectObject: wetSound
Extract part: 0, inputDur, "rectangular", 1, "no"
wetTrimmed = selected("Sound")
removeObject: wetSound

# Mix wet/dry
if wet_level < 1.0
    # Need to mix with dry
    dry_str$ = string$(dry_level)
    wet_str$ = string$(wet_level)
    input_str$ = string$(inputID)
    
    selectObject: wetTrimmed
    Formula: "self * " + wet_str$ + " + object[" + input_str$ + "] * " + dry_str$
endif

selectObject: wetTrimmed
Scale peak: 0.95
Rename: inputName$ + "_room_" + presetName$
result = selected("Sound")

# ==============================================================================
# 10) Visualization
# ==============================================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.58
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.95, "half", "##Artificial Room##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... inputName$ + "  |  " + presetName$
        ... + "  |  " + fixed$(roomL, 1) + "×" + fixed$(roomW, 1)
        ... + "×" + fixed$(roomH, 1) + "m"
        ... + "  |  Wet=" + fixed$(wet_dry_percent, 0) + "%"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.42
    Select inner viewport: 0.55, 7.65, 0.57, 1.37
    selectObject: inputID
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    Text top: "no", "Input: " + inputName$

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.46, 2.36
    Select inner viewport: 0.55, 7.65, 1.51, 2.31
    selectObject: result
    Colour: "{0.45, 0.58, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Wet " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # RT60 bar chart (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.44, 3.94
    Select inner viewport: 0.55, 3.85, 2.54, 3.84

    maxRT = 0
    for b from 1 to 6
        if t60[b] > maxRT
            maxRT = t60[b]
        endif
    endfor
    maxRT = maxRT * 1.15

    Axes: 0.3, 6.7, 0, maxRT
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.3, 6.7, 0, maxRT

    bandLabels$[1] = "125"
    bandLabels$[2] = "250"
    bandLabels$[3] = "500"
    bandLabels$[4] = "1k"
    bandLabels$[5] = "2k"
    bandLabels$[6] = "4k"

    for b from 1 to 6
        cR = 0.80 - b * 0.05
        cG = 0.50 + b * 0.03
        cB = 0.40 + b * 0.08
        barCol$ = "{" + fixed$(cR, 2) + ", " + fixed$(cG, 2) + ", " + fixed$(cB, 2) + "}"
        Paint rectangle: barCol$, b - 0.35, b + 0.35, 0, t60[b]
        Colour: "{0.35, 0.35, 0.35}"
        Font size: 5
        Text: b, "centre", -maxRT * 0.07, "half", bandLabels$[b]
        Text: b, "centre", t60[b] + maxRT * 0.04, "half", fixed$(t60[b], 2)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "RT60 (s)"
    Text bottom: "yes", "Hz"
    Text top: "no", "RT60 per octave band  (Eyring)"

    # ----------------------------------------------------------
    # IR waveform (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.44, 3.94
    Select inner viewport: 4.40, 7.65, 2.54, 3.84
    selectObject: irFinal
    Colour: "{0.58, 0.70, 0.45}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "IR"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Impulse response  (" + fixed$(ir_length, 2) + " s)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.04, 4.94
    Select inner viewport: 0.55, 7.65, 4.10, 4.88
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.55, "half",
        ... "Room: " + fixed$(roomL, 1) + "×" + fixed$(roomW, 1)
        ... + "×" + fixed$(roomH, 1) + "m"
        ... + "  |  Vol: " + fixed$(v, 0) + " m³"
        ... + "  |  Surface: " + fixed$(stotal, 0) + " m²"
        ... + "  |  Floor: " + mFloor$
        ... + "  |  Ceil: " + mCeil$
        ... + "  |  Wall: " + mW1$
    Text: 0.02, "left", 0.22, "half",
        ... "RT60 @1kHz: " + fixed$(t60_4, 2) + " s"
        ... + "  |  IR: " + fixed$(ir_length, 2) + " s"
        ... + "  |  Predelay: " + fixed$(iR_predelay_ms, 0) + " ms"
        ... + "  |  Early refl: " + string$(early_reflections_count)
        ... + "  |  Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ==============================================================================
# 11) Cleanup
# ==============================================================================

if keep_IR = 0
    removeObject: irFinal
endif

# ==============================================================================
# 12) Final
# ==============================================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
if keep_IR
    appendInfoLine: "IR kept: IR_", presetName$
endif

if play_result
    selectObject: result
    Play
endif

selectObject: result