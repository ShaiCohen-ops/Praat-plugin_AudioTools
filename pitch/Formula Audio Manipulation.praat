# ============================================================
# Praat AudioTools - Formula Audio Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ===================================================================
#  Advanced Formula Audio Manipulation
#  Applies complex modulations to selected audio
# ===================================================================

form Advanced Formula Audio Manipulation
    comment === MODULATION PARAMETERS ===
    real Base_frequency 0.8
    real Modulation_depth 0.85
    integer Complexity_level 3
    comment === PITCH MODULATION ===
    boolean Apply_pitch_modulation 1
    real Pitch_mod_rate 0.5
    real Pitch_mod_depth 0.4
    comment === RING MODULATION ===
    boolean Apply_ring_modulation 1
    real Ring_mod_frequency 120
    real Ring_mod_depth 0.6
endform

# Get selected Sound
sound = selected("Sound")
sound_name$ = selected$("Sound")
duration = Get total duration
sampling_rate = Get sampling frequency

writeInfoLine: "Creating Advanced Formula Manipulation..."

# ===================================================================
# BUILD AMPLITUDE MODULATION ENVELOPE
# ===================================================================

if complexity_level = 1
    # Simple modulated envelope
    formula$ = "(0.5 + 0.5*sin(2*pi*'base_frequency'*x * (1 + 'modulation_depth'*0.6*sin(2*pi*2*x))))"
    
elsif complexity_level = 2
    # Multiple competing oscillators
    formula$ = "0.5 + 0.5*("
    formula$ = formula$ + "sin(2*pi*'base_frequency'*x * (1 + 0.4*sin(2*pi*1.5*x))) + "
    formula$ = formula$ + "0.6*sin(2*pi*'base_frequency'*1.618*x * (1 + 0.5*sin(2*pi*2.8*x))) + "
    formula$ = formula$ + "0.4*sin(2*pi*'base_frequency'*2.718*x * (1 + 0.6*sin(2*pi*0.9*x)))"
    formula$ = formula$ + ") / 2.0"
    
else
    # Complex chaotic system
    formula$ = "0.5 + 0.5*("
    formula$ = formula$ + "sin(2*pi*'base_frequency'*x * "
    formula$ = formula$ + "(1 + 'modulation_depth'*0.7*sin(2*pi*1.4*x + 2.5*sin(2*pi*0.4*x)))) + "
    formula$ = formula$ + "0.8*sin(2*pi*'base_frequency'*1.618*x * "
    formula$ = formula$ + "(1 + 'modulation_depth'*0.6*sin(2*pi*2.5*x + 1.5*sin(2*pi*0.7*x)))) + "
    formula$ = formula$ + "0.5*sin(2*pi*'base_frequency'*2.414*x * "
    formula$ = formula$ + "(1 + 'modulation_depth'*0.8*sin(2*pi*1.1*x + 2.0*sin(2*pi*0.3*x))))"
    formula$ = formula$ + ") / 2.3"
endif

Create Sound from formula: "am_envelope", 1, 0, duration, sampling_rate, formula$
am_envelope = selected("Sound")

# ===================================================================
# APPLY AMPLITUDE MODULATION
# ===================================================================

selectObject: sound
Copy: sound_name$ + "_modulated"
sound_mod = selected("Sound")
Formula: "self * object[am_envelope, col]"

# ===================================================================
# PITCH MODULATION (optional)
# ===================================================================

if apply_pitch_modulation
    selectObject: sound_mod
    To Manipulation: 0.01, 75, 600
    manipulation = selected("Manipulation")
    
    # Extract and remove original pitch tier
    pitchtier_original = Extract pitch tier
    Remove
    
    # Get base pitch
    selectObject: sound_mod
    To Pitch: 0, 75, 600
    pitch = selected("Pitch")
    f0_base = Get mean: 0, 0, "Hertz"
    
    if f0_base = undefined
        f0_base = 150
    endif
    
    # Create modulated pitch tier
    selectObject: manipulation
    Create PitchTier: sound_name$ + "_pitch_mod", 0, duration
    pitchtier_new = selected("PitchTier")
    
    # Generate pitch modulation
    n_points = floor(duration * 50)
    for i from 1 to n_points
        t = (i - 1) / 50
        # Chaotic pitch modulation
        mod_factor = 1 + pitch_mod_depth * sin(2*pi*pitch_mod_rate*t + 1.5*sin(2*pi*0.3*t))
        f0 = f0_base * mod_factor
        
        selectObject: pitchtier_new
        Add point: t, f0
    endfor
    
    # Replace pitch tier
    selectObject: manipulation
    plus pitchtier_new
    Replace pitch tier
    removeObject: pitchtier_new
    
    # Resynthesize
    selectObject: manipulation
    sound_repitched = Get resynthesis (overlap-add)
    Rename: sound_name$ + "_pitch_mod"
    
    # Clean up
    removeObject: sound_mod, pitch, manipulation
    sound_mod = sound_repitched
endif

# ===================================================================
# RING MODULATION (optional)
# ===================================================================

if apply_ring_modulation
    # Create carrier signal
    carrier_formula$ = "sin(2*pi*'ring_mod_frequency'*x)"
    Create Sound from formula: "carrier", 1, 0, duration, sampling_rate, carrier_formula$
    carrier = selected("Sound")
    
    # Apply ring modulation
    selectObject: sound_mod
    ring_formula$ = "self * (1 - 'ring_mod_depth' + 'ring_mod_depth' * object[carrier, col])"
    Formula: ring_formula$
    
    removeObject: carrier
endif
Play

# ===================================================================
# CLEANUP & SELECT OUTPUT
# ===================================================================

selectObject: sound_mod
Rename: sound_name$ + "_formula_manipulated"
Scale peak: 0.95

removeObject: am_envelope

appendInfoLine: "✓ Advanced Formula Manipulation complete!"
appendInfoLine: "  Complexity level: ", complexity_level
appendInfoLine: "  Base modulation frequency: ", fixed$(base_frequency, 2), " Hz"
appendInfoLine: "  Modulation depth: ", fixed$(modulation_depth, 2)
if apply_pitch_modulation
    appendInfoLine: "  Pitch modulation: ON (", fixed$(pitch_mod_rate, 2), " Hz, depth ", fixed$(pitch_mod_depth, 2), ")"
endif
if apply_ring_modulation
    appendInfoLine: "  Ring modulation: ON (", ring_mod_frequency, " Hz, depth ", fixed$(ring_mod_depth, 2), ")"
endif