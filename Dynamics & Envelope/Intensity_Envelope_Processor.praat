# ============================================================
# Praat AudioTools - Intensity_Envelope_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-mode intensity envelope processor with power shaping,
#   tremolo, gating, time manipulation, and envelope inversion.
#
# Changelog v1.1:
#   - Added presets
#   - Added gate duty cycle and smoothing
#   - Added tremolo phase control
#   - Added info output
#   - Improved visualization with comparison
#   - Added random modulation mode
#   - Fixed gating clicks with smoothing
# ============================================================

form Intensity Envelope Processor v1.1
    optionmenu Preset 1
        option Custom
        option Soft Compression
        option Hard Expansion
        option Gentle Tremolo
        option Fast Tremolo
        option Rhythmic Chop
        option Smooth Gate
        option Tape Slowdown
        option Reverse Dynamics
        option Random Flutter
    optionmenu Mode 3
        option Power Shaping (dynamics)
        option Sine Modulation (tremolo)
        option Rhythmic Gating (chopper)
        option Time Shift
        option Time Scaling (tape speed)
        option Envelope Inversion
        option Random Modulation
    comment === Power Shaping ===
    real Exponent 2.0
    comment (<1 = compress, >1 = expand)
    comment === Tremolo ===
    positive Tremolo_rate_Hz 5.0
    real Tremolo_depth 0.5
    real Tremolo_center 0.5
    real Tremolo_phase 0
    comment === Gating ===
    positive Gate_rate_Hz 4.0
    real Gate_duty_percent 50
    real Gate_max 1.0
    real Gate_min 0.0
    positive Gate_smoothing_ms 5
    comment === Time Manipulation ===
    real Shift_seconds 0.1
    positive Scale_factor 1.5
    comment (0.5 = double speed, 2.0 = half speed)
    comment === Random Modulation ===
    positive Random_rate_Hz 8
    real Random_depth 0.3
    integer Random_seed 0
    comment (0 = different each time)
    comment === Output ===
    boolean Normalize 1
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

source_id = selected("Sound")
source_name$ = selected$("Sound")

selectObject: source_id
dur = Get total duration
orig_sr = Get sampling frequency

# === APPLY PRESETS ===
if preset = 2
    # Soft Compression
    mode = 1
    exponent = 0.5
    presetName$ = "SoftComp"
elsif preset = 3
    # Hard Expansion
    mode = 1
    exponent = 3.0
    presetName$ = "HardExp"
elsif preset = 4
    # Gentle Tremolo
    mode = 2
    tremolo_rate_Hz = 3
    tremolo_depth = 0.3
    tremolo_center = 0.7
    presetName$ = "GentleTrem"
elsif preset = 5
    # Fast Tremolo
    mode = 2
    tremolo_rate_Hz = 8
    tremolo_depth = 0.5
    tremolo_center = 0.5
    presetName$ = "FastTrem"
elsif preset = 6
    # Rhythmic Chop
    mode = 3
    gate_rate_Hz = 4
    gate_duty_percent = 50
    gate_max = 1
    gate_min = 0
    gate_smoothing_ms = 2
    presetName$ = "RhythmChop"
elsif preset = 7
    # Smooth Gate
    mode = 3
    gate_rate_Hz = 2
    gate_duty_percent = 70
    gate_max = 1
    gate_min = 0.1
    gate_smoothing_ms = 20
    presetName$ = "SmoothGate"
elsif preset = 8
    # Tape Slowdown
    mode = 5
    scale_factor = 2.0
    presetName$ = "TapeSlowdown"
elsif preset = 9
    # Reverse Dynamics
    mode = 6
    presetName$ = "ReverseDyn"
elsif preset = 10
    # Random Flutter
    mode = 7
    random_rate_Hz = 12
    random_depth = 0.25
    presetName$ = "Flutter"
else
    presetName$ = "Custom"
endif

# === GET MODE NAME ===
if mode = 1
    modeName$ = "Power Shaping"
elsif mode = 2
    modeName$ = "Tremolo"
elsif mode = 3
    modeName$ = "Gating"
elsif mode = 4
    modeName$ = "Time Shift"
elsif mode = 5
    modeName$ = "Time Scale"
elsif mode = 6
    modeName$ = "Inversion"
else
    modeName$ = "Random"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  INTENSITY ENVELOPE PROCESSOR v1.1"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", source_name$, " (", fixed$(dur, 3), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: "Mode: ", modeName$
writeInfoLine: ""

# ============================================================
# CREATE MODULATOR
# ============================================================

selectObject: source_id
To Intensity: 100, 0, "yes"
intensity_id = selected("Intensity")

# Start with flat 1.0 (full volume)
Formula: ~ 1
Rename: "modulator"
modulator_id = selected("Intensity")

# ============================================================
# APPLY MODE-SPECIFIC ENVELOPE
# ============================================================

appendInfoLine: "Processing mode: ", modeName$, "..."

if mode = 1
    # === POWER SHAPING ===
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    temp_int_id = selected("Intensity")
    max_db = Get maximum: 0, 0, "Parabolic"
    
    selectObject: modulator_id
    Formula: ~ 10 ^ ((object(temp_int_id, x) - max_db) / 20)
    Formula: ~ self ^ exponent
    
    removeObject: temp_int_id
    
    appendInfoLine: "  Exponent: ", fixed$(exponent, 2)
    if exponent < 1
        appendInfoLine: "  Effect: Compression (louder parts reduced)"
    else
        appendInfoLine: "  Effect: Expansion (louder parts boosted)"
    endif

elsif mode = 2
    # === TREMOLO ===
    selectObject: modulator_id
    Formula: ~ tremolo_center + tremolo_depth * sin(2 * pi * tremolo_rate_Hz * x + tremolo_phase * pi / 180)
    Formula: ~ min(max(self, 0), 1)
    
    appendInfoLine: "  Rate: ", fixed$(tremolo_rate_Hz, 1), " Hz"
    appendInfoLine: "  Depth: ", fixed$(tremolo_depth * 100, 0), "%"
    appendInfoLine: "  Center: ", fixed$(tremolo_center, 2)

elsif mode = 3
    # === RHYTHMIC GATING (with smoothing) ===
    duty = gate_duty_percent / 100
    smoothSec = gate_smoothing_ms / 1000
    period = 1 / gate_rate_Hz
    riseWidth = smoothSec * gate_rate_Hz
    
    selectObject: modulator_id
    
    # Gating formula with smooth transitions using cosine interpolation
    # phase = position within cycle (0-1)
    # riseWidth = portion of cycle used for rising edge
    # duty = portion of cycle that's "on"
    Formula: ~ if ((x * gate_rate_Hz) mod 1) < riseWidth then gate_min + (gate_max - gate_min) * (0.5 - 0.5 * cos(pi * ((x * gate_rate_Hz) mod 1) / riseWidth)) else if ((x * gate_rate_Hz) mod 1) < duty then gate_max else if ((x * gate_rate_Hz) mod 1) < duty + riseWidth then gate_max - (gate_max - gate_min) * (0.5 - 0.5 * cos(pi * (((x * gate_rate_Hz) mod 1) - duty) / riseWidth)) else gate_min fi fi fi
    
    appendInfoLine: "  Rate: ", fixed$(gate_rate_Hz, 1), " Hz"
    appendInfoLine: "  Duty: ", fixed$(gate_duty_percent, 0), "%"
    appendInfoLine: "  Smoothing: ", fixed$(gate_smoothing_ms, 0), " ms"

elsif mode = 6
    # === ENVELOPE INVERSION ===
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    temp_int_id = selected("Intensity")
    max_db = Get maximum: 0, 0, "Parabolic"
    
    selectObject: modulator_id
    Formula: ~ 10 ^ ((object(temp_int_id, x) - max_db) / 20)
    Formula: ~ 1 - self
    
    removeObject: temp_int_id
    
    appendInfoLine: "  Effect: Loud becomes quiet, quiet becomes loud"

elsif mode = 7
    # === RANDOM MODULATION ===
    selectObject: modulator_id
    
    # Create smoothed random modulation
    Formula: ~ randomUniform(1 - random_depth, 1)
    
    # Smooth by averaging neighbors
    smoothSamples = round(orig_sr / random_rate_Hz / 10)
    if smoothSamples < 2
        smoothSamples = 2
    endif
    
    # Multiple smoothing passes for organic feel
    for pass to 5
        Formula: ~ if col > smoothSamples and col < ncol - smoothSamples then (self[col - smoothSamples] + 2 * self[col] + self[col + smoothSamples]) / 4 else self fi
    endfor
    
    appendInfoLine: "  Rate: ~", fixed$(random_rate_Hz, 1), " Hz"
    appendInfoLine: "  Depth: ", fixed$(random_depth * 100, 0), "%"

endif

# ============================================================
# APPLY PROCESSING
# ============================================================

if mode = 4
    # === TIME SHIFT ===
    selectObject: source_id
    result_id = Copy: source_name$ + "_shifted"
    Shift times to: "start time", shift_seconds
    
    appendInfoLine: "  Shift: ", fixed$(shift_seconds, 3), " s"

elsif mode = 5
    # === TIME SCALING (Tape Speed) ===
    selectObject: source_id
    temp_id = Copy: source_name$ + "_temp"
    Override sampling frequency: orig_sr / scale_factor
    Resample: orig_sr, 50
    Rename: source_name$ + "_scaled"
    result_id = selected("Sound")
    removeObject: temp_id
    
    new_dur = dur * scale_factor
    appendInfoLine: "  Scale: ", fixed$(scale_factor, 2), "x"
    appendInfoLine: "  New duration: ", fixed$(new_dur, 3), " s"
    if scale_factor > 1
        appendInfoLine: "  Effect: Slower, lower pitch"
    else
        appendInfoLine: "  Effect: Faster, higher pitch"
    endif

else
    # === ENVELOPE-BASED MODES ===
    
    # Keep visualization copy (linear 0-1)
    selectObject: modulator_id
    vis_modulator_id = Copy: "vis_mod"
    
    # Convert to dB for IntensityTier
    selectObject: modulator_id
    Formula: ~ max(self, 0.00001)
    Formula: ~ 20 * log10(self)
    
    # Create tier and multiply
    mod_tier_id = Down to IntensityTier
    selectObject: source_id
    plusObject: mod_tier_id
    Multiply
    Rename: source_name$ + "_" + presetName$
    result_id = selected("Sound")
    
    removeObject: mod_tier_id
endif

# === NORMALIZE ===
if normalize
    selectObject: result_id
    Scale peak: 0.95
endif

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Font size: 10
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Intensity Processor## | " + modeName$ + " | " + presetName$
    
    if mode = 4 or mode = 5
        # --- TIME MANIPULATION MODES ---
        
        # Original
        Select outer viewport: 0, 8, 0.5, 2.2
        Select inner viewport: 0.8, 7.6, 0.7, 2.0
        selectObject: source_id
        Colour: "{0.5, 0.5, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Select outer viewport: 0.15, 8, 0.5, 2.2
        Text left: "yes", "Original"
        
        # Result
        Select outer viewport: 0, 8, 2.3, 4.0
        Select inner viewport: 0.8, 7.6, 2.5, 3.8
        selectObject: result_id
        Colour: "{0.3, 0.6, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Select outer viewport: 0.15, 8, 2.3, 4.0
        Text left: "yes", "Result"
        Text bottom: "yes", "Time (s)"
        
    else
        # --- ENVELOPE MODES ---
        
        # Original waveform (top)
        Select outer viewport: 0, 8, 0.5, 1.7
        Select inner viewport: 0.8, 7.6, 0.6, 1.5
        selectObject: source_id
        Colour: "{0.5, 0.5, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 0.5, 1.7
        Text left: "yes", "Input"
        
        # Envelope (middle)
        Select outer viewport: 0, 8, 1.8, 3.0
        Select inner viewport: 0.8, 7.6, 1.9, 2.8
        
        # Background
        Axes: 0, dur, 0, 1.1
        Paint rectangle: "{0.95, 0.98, 0.95}", 0, dur, 0, 1.1
        
        # Unity reference
        Colour: "{0.7, 0.7, 0.7}"
        Dashed line
        Draw line: 0, 1, dur, 1
        Solid line
        
        # Envelope curve
        selectObject: vis_modulator_id
        Colour: "{0.2, 0.7, 0.3}"
        Line width: 2
        Draw: 0, 0, 0, 1.1, "no"
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 1.8, 3.0
        Text left: "yes", "Envelope"
        
        # Result waveform (bottom)
        Select outer viewport: 0, 8, 3.1, 4.3
        Select inner viewport: 0.8, 7.6, 3.2, 4.1
        selectObject: result_id
        Colour: "{0.3, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 3.1, 4.3
        Text left: "yes", "Result"
        Text bottom: "yes", "Time (s)"
        
        # Parameters
        Select outer viewport: 0, 8, 4.4, 4.8
        Font size: 6
        Colour: "{0.4, 0.4, 0.4}"
        
        if mode = 1
            Text: 0.5, "centre", 0.5, "half", "Exponent: " + fixed$(exponent, 2)
        elsif mode = 2
            Text: 0.5, "centre", 0.5, "half", "Rate: " + fixed$(tremolo_rate_Hz, 1) + "Hz | Depth: " + fixed$(tremolo_depth * 100, 0) + "% | Center: " + fixed$(tremolo_center, 2)
        elsif mode = 3
            Text: 0.5, "centre", 0.5, "half", "Rate: " + fixed$(gate_rate_Hz, 1) + "Hz | Duty: " + fixed$(gate_duty_percent, 0) + "% | Smooth: " + fixed$(gate_smoothing_ms, 0) + "ms"
        elsif mode = 7
            Text: 0.5, "centre", 0.5, "half", "Rate: ~" + fixed$(random_rate_Hz, 1) + "Hz | Depth: " + fixed$(random_depth * 100, 0) + "%"
        endif
        
        removeObject: vis_modulator_id
    endif
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

nocheck removeObject: intensity_id
nocheck removeObject: modulator_id

selectObject: result_id

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result_id