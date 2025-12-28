# ============================================================
# Praat AudioTools - Spectral Effects Suite
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified spectral manipulation effects combining frequency modulation,
#   amplitude modulation, and temporal envelopes
# ============================================================

form Spectral Effects Suite
    comment === EFFECT TYPE ===
    optionmenu Effect: 1
        option Wobble (freq mod + tremolo decay)
        option Wobbling Shift (freq shift + turbulent decay)
        option Oscillating Decay (spectral filter + osc)
        option Underwater (muffled + bubbling)
        option Reverse Crescendo (spectral + fade-in)
        option Pulsing Reversal (spectral + rhythmic decay)
    
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Subtle
        option Moderate
        option Strong
        option Extreme
    
    comment === SPECTRAL PARAMETERS ===
    positive Spectral_shift_base 1.1
    positive Spectral_depth 0.3
    positive Spectral_cycles 50
    comment (Cycles for wobble/modulation effects)
    
    comment === AMPLITUDE ENVELOPE ===
    optionmenu Envelope_type: 1
        option Exponential Decay
        option Exponential Crescendo
        option Tremolo with Decay
        option Random Bubbling
        option Turbulent Decay (Gaussian)
        option Rhythmic Pulsing (abs sin)
    positive Envelope_strength 10
    comment (Higher = stronger effect)
    
    comment === MODULATION ===
    positive Modulation_center 1.0
    positive Modulation_depth 0.5
    positive Modulation_cycles 20
    comment (For tremolo/oscillation/pulsing effects)
    
    comment === OUTPUT ===
    positive Scale_peak 0.99
    boolean Play_after 1
endform

# ===================================================================
# PRESET APPLICATION
# ===================================================================

if preset = 2
    # Subtle
    spectral_depth = 0.1
    modulation_depth = 0.2
    envelope_strength = 5
    preset_name$ = "Subtle"
elsif preset = 3
    # Moderate
    spectral_depth = 0.3
    modulation_depth = 0.5
    envelope_strength = 10
    preset_name$ = "Moderate"
elsif preset = 4
    # Strong
    spectral_depth = 0.5
    modulation_depth = 0.7
    envelope_strength = 15
    preset_name$ = "Strong"
elsif preset = 5
    # Extreme
    spectral_depth = 0.7
    modulation_depth = 0.9
    envelope_strength = 25
    spectral_cycles = 80
    modulation_cycles = 40
    preset_name$ = "Extreme"
else
    preset_name$ = "Custom"
endif

# ===================================================================
# EFFECT-SPECIFIC ADJUSTMENTS
# ===================================================================

if effect = 1
    # Wobble (original wobble effect)
    effect_name$ = "Wobble"
    envelope_type = 3
    
elsif effect = 2
    # Wobbling Shift (simpler wobble with turbulent decay)
    effect_name$ = "WobblingShift"
    spectral_depth = spectral_depth * 0.3
    envelope_type = 5
    
elsif effect = 3
    # Oscillating Decay
    effect_name$ = "OscillatingDecay"
    spectral_shift_base = 1.1
    envelope_type = 1
    
elsif effect = 4
    # Underwater
    effect_name$ = "Underwater"
    envelope_type = 4
    if preset > 1 and (preset = 4 or preset = 5)
        spectral_shift_base = 1.15
    endif
    
elsif effect = 5
    # Reverse Crescendo
    effect_name$ = "ReverseCrescendo"
    envelope_type = 2
    spectral_shift_base = 1.1
    
else
    # Pulsing Reversal
    effect_name$ = "PulsingReversal"
    spectral_shift_base = 1.2
    envelope_type = 6
    if preset = 1
        modulation_cycles = 15
    endif
endif

# ===================================================================
# PROCESSING
# ===================================================================

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Copy the sound object
original_name$ = selected$("Sound")
Copy: "processing"
sound = selected("Sound")

writeInfoLine: "Spectral Effects Suite"
appendInfoLine: "Effect: ", effect_name$
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: ""

# ===================================================================
# STEP 1: SPECTRAL MANIPULATION
# ===================================================================

if effect = 1
    # WOBBLE: Dual frequency modulation (original wobble)
    appendInfoLine: "Applying wobble frequency modulation..."
    Formula: "self[col/(spectral_shift_base + spectral_depth * sin(spectral_cycles * (x-xmin) / (xmax-xmin)))] - self[col*(spectral_shift_base + spectral_depth * cos(spectral_cycles * (x-xmin) / (xmax-xmin)))]"
    
elsif effect = 2
    # WOBBLING SHIFT: Single wobble with dual components
    appendInfoLine: "Applying wobbling frequency shift..."
    Formula: "self[col/(spectral_shift_base + spectral_depth * sin(spectral_cycles * (x-xmin) / (xmax-xmin)))] - self[col*(spectral_shift_base + spectral_depth * cos(spectral_cycles * (x-xmin) / (xmax-xmin)))]"
    
elsif effect = 3
    # OSCILLATING DECAY: Simple spectral filtering
    appendInfoLine: "Applying spectral filtering..."
    high_factor = spectral_shift_base
    low_factor = spectral_shift_base
    Formula: "self[col/low_factor] - self[col*high_factor]"
    
elsif effect = 4
    # UNDERWATER: Multi-band averaging + high freq removal
    appendInfoLine: "Applying underwater muffling..."
    f1 = spectral_shift_base
    f2 = spectral_shift_base + 0.03
    f3 = spectral_shift_base + 0.07
    hf = spectral_shift_base + 0.2
    Formula: "(self[col/f1] + self[col/f2] + self[col/f3]) / 3 - self[col*hf]"
    
elsif effect = 5
    # REVERSE CRESCENDO: Simple spectral filtering
    appendInfoLine: "Applying spectral filtering..."
    high_factor = spectral_shift_base
    low_factor = spectral_shift_base
    Formula: "self[col/low_factor] - self[col*high_factor]"
    
else
    # PULSING REVERSAL: Spectral reversal
    appendInfoLine: "Applying spectral reversal..."
    high_factor = spectral_shift_base
    low_factor = spectral_shift_base
    Formula: "self[col/low_factor] - self[col*high_factor]"
endif

# ===================================================================
# STEP 2: AMPLITUDE ENVELOPE
# ===================================================================

if envelope_type = 1
    # Exponential Decay
    appendInfoLine: "Applying exponential decay..."
    Formula: "self * envelope_strength^(-(x-xmin)/(xmax-xmin))"
    
elsif envelope_type = 2
    # Exponential Crescendo (reverse)
    appendInfoLine: "Applying exponential crescendo..."
    Formula: "self * envelope_strength^((x-xmin)/(xmax-xmin)-1)"
    
elsif envelope_type = 3
    # Tremolo with Decay
    appendInfoLine: "Applying tremolo with decay..."
    Formula: "self * envelope_strength^(-(x-xmin)/(xmax-xmin)) * (modulation_center + modulation_depth * sin(modulation_cycles * (x-xmin) / (xmax-xmin)))"
    
elsif envelope_type = 4
    # Random Bubbling
    appendInfoLine: "Applying random bubbling..."
    Formula: "self * envelope_strength^(-(x-xmin)/(xmax-xmin)) * (modulation_center + modulation_depth * randomUniform(-1, 1))"
    
elsif envelope_type = 5
    # Turbulent Decay (Gaussian)
    appendInfoLine: "Applying turbulent decay..."
    Formula: "self * envelope_strength^(-(x-xmin)/(xmax-xmin)) * (modulation_center + modulation_depth * randomGauss(0, 1))"
    
else
    # Rhythmic Pulsing (abs sin)
    appendInfoLine: "Applying rhythmic pulsing..."
    Formula: "self * abs(sin(modulation_cycles * (x-xmin) / (xmax-xmin))) * envelope_strength^(-(x-xmin)/(xmax-xmin))"
endif

# ===================================================================
# FINALIZE
# ===================================================================

appendInfoLine: "Scaling to peak..."
Scale peak: scale_peak

# Rename output
Rename: original_name$ + "_" + effect_name$ + "_" + preset_name$

appendInfoLine: ""
appendInfoLine: "✓ Processing complete!"

if play_after
    Play
endif