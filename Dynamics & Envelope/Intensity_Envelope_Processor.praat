# ============================================================
# Praat AudioTools - Intensity_Envelope_Processor
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Intensity_Envelope_Processor
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Intensity Envelope Processor
    comment Select the Mode you want to use:
    optionmenu mode 3
        option Power Shaping (Exp/Comp)
        option Sine Modulation (Tremolo)
        option Rhythmic Gating (Chopper)
        option Time Shift
        option Time Scaling (Tape Speed)
        option Wave Inversion
    
    comment ---------------------------------------------------------------
    comment [1] Power Shaping Params:
    real exponent 3.0
    
    comment [2] Tremolo Params:
    positive tremolo_rate 5.0
    positive tremolo_depth 0.5
    real tremolo_center 0.5
    
    comment [3] Gating Params:
    positive gate_rate 4.0
    real gate_max 1.0
    real gate_min 0.0
    
    comment [4] Time Shift Params:
    real shift_seconds 0.1
    
    comment [5] Time Scale Params (0.5=Double Speed, 2.0=Half Speed):
    positive scale_factor 1.5
    
    comment ---------------------------------------------------------------
    boolean scale_output_peak 1
    boolean show_visualization 1
    boolean play_after_processing 1
endform

# ============================================================
# 1. SETUP
# ============================================================

# Check selection
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

source_id = selected("Sound")
source_name$ = selected$("Sound")
selectObject: source_id
dur = Get total duration
orig_sr = Get sampling frequency

# Create working copies
# We generate an Intensity object to get the time grid
To Intensity: 100, 0, "yes"
intensity_id = selected("Intensity")

# Create a "Canvas" for our modulator (Linear 0-1)
# We start with a flat line of 1.0 (Full volume)
Formula: "1"
Rename: "modulator_linear"
modulator_id = selected("Intensity")

# ============================================================
# 2. CALCULATE ENVELOPE SHAPE (LINEAR 0-1 MATH)
# ============================================================

selectObject: modulator_id

if mode = 1
    # Power Shaping
    # 1. Get info from source
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    temp_int_id = selected("Intensity")
    max_db = Get maximum: 0, 0, "Parabolic"
    
    # 2. Apply formula directly to modulator using object reference
    # (Avoids creating new objects with 'Add')
    selectObject: modulator_id
    
    # First, copy the normalized shape from temp
    # Formula logic: 10^((dB - max)/20)
    Formula: "10 ^ ((object(" + string$(temp_int_id) + ", x) - " + string$(max_db) + ") / 20)"
    
    # Second, apply exponent
    Formula: "self ^ " + string$(exponent)
    
    removeObject: temp_int_id
    selectObject: modulator_id

elsif mode = 2
    # Sine Modulation (Tremolo)
    Formula: string$(tremolo_center) + " + (" + string$(tremolo_depth) + " * sin(2 * pi * x * " + string$(tremolo_rate) + "))"
    Formula: "min(max(self, 0), 1)"

elsif mode = 3
    # Rhythmic Gating
    Formula: "if sin(2 * pi * x * " + string$(gate_rate) + ") > 0 then " + string$(gate_max) + " else " + string$(gate_min) + " fi"

elsif mode = 6
    # Inversion
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    temp_int_id = selected("Intensity")
    max_db = Get maximum: 0, 0, "Parabolic"
    
    selectObject: modulator_id
    # Copy normalized shape
    Formula: "10 ^ ((object(" + string$(temp_int_id) + ", x) - " + string$(max_db) + ") / 20)"
    # Invert
    Formula: "1 - self"
    
    removeObject: temp_int_id
    selectObject: modulator_id

endif

# ============================================================
# 3. APPLY PROCESSING (CONVERT TO dB FOR TIER)
# ============================================================

if mode = 4
    # --- Time Shift ---
    selectObject: source_id
    result_id = Copy: source_name$ + "_shifted"
    Shift times to: "start time", shift_seconds

elsif mode = 5
    # --- Time Scaling (Tape Speed) ---
    selectObject: source_id
    temp_id = Copy: source_name$ + "_temp"
    Override sampling frequency: orig_sr / scale_factor
    Resample: orig_sr, 50
    Rename: source_name$ + "_scaled"
    result_id = selected("Sound")
    removeObject: temp_id

else
    # --- Envelope Modes (Multiplication) ---
    
    # 1. Visualization Copy (Linear)
    selectObject: modulator_id
    vis_modulator_id = Copy: "vis_mod"
    
    # 2. Convert Modulator to dB (for IntensityTier)
    selectObject: modulator_id
    Formula: "max(self, 0.00001)"
    Formula: "20 * log10(self)"
    
    # 3. Create Tier and Multiply
    mod_tier_id = Down to IntensityTier
    selectObject: source_id
    plusObject: mod_tier_id
    Multiply
    Rename: source_name$ + "_processed"
    result_id = selected("Sound")
    
    # Cleanup Tier
    removeObject: mod_tier_id
endif

# Output Scaling
if scale_output_peak
    selectObject: result_id
    Scale peak: 0.99
endif

# ============================================================
# 4. VISUALIZATION
# ============================================================

if show_visualization
    Erase all
    Font size: 10
    
    # --- TOP PANEL: MODULATOR (LINEAR VIEW) ---
    Select outer viewport: 0, 6, 0, 4
    
    if mode = 4 or mode = 5
        selectObject: source_id
        Black
        Draw: 0, 0, 0, 0, "no", "Curve"
        Text top: "no", "Original Sound (Time Manipulation)"
    else
        # Draw the Linear Modulator
        selectObject: vis_modulator_id
        Colour: "{0, 0.8, 0}"
        Line width: 2
        Draw: 0, 0, 0, 1, "no"
        Line width: 1
        
        Colour: "Silver"
        Draw inner box
        Axes: 0, dur, 0, 1
        Marks left every: 1, 0.2, "yes", "yes", "no"
        Text left: "yes", "Linear Gain (0-1)"
        
        Black
        Text top: "no", "Applied Envelope Shape (0=Silence, 1=Full)"
        
        removeObject: vis_modulator_id
    endif

    # --- BOTTOM PANEL: RESULT ---
    Select outer viewport: 0, 6, 4.5, 8.5
    
    # Draw Result Sound
    selectObject: result_id
    Black
    Draw: 0, 0, 0, 0, "no", "Curve"
    Draw inner box
    Text top: "no", "Resulting Waveform"
    
endif

# ============================================================
# 5. CLEANUP
# ============================================================

# Play result
if play_after_processing
    selectObject: result_id
    Play
endif

# Safe Removal (nocheck prevents crash if objects are missing)
nocheck removeObject: intensity_id
nocheck removeObject: modulator_id

# Ensure only the final result is selected
selectObject: result_id