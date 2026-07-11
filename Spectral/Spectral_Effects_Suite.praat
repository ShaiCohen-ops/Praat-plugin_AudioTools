# ============================================================
# Praat AudioTools - Spectral Effects Suite
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified spectral manipulation effects combining frequency modulation,
#   amplitude modulation, and temporal envelopes
#
# Changelog v1.2 (2026):
#   - FIX (audible, all six effects): the spectral formulas read
#     self[col/f] IN PLACE -- Praat's Formula overwrites columns
#     left to right, so col/f (always below col) returned the
#     just-written OUTPUT, not the input: the down-shifted term
#     was a recursive self-composition, out[k] = out[k/f] - in[k*f]
#     instead of the intended in[k/f] - in[k*f] ("frequency
#     modulation" per the header; ~96 recursion levels deep at the
#     end of a 10 s file). v1.2 freezes a copy of the pre-effect
#     signal and reads both terms from it via object[] -- the
#     stated symmetric structure, now real. Non-integer index
#     rounding is identical between self[] and object[] (verified
#     on 6.4.42), so the classic resampling-read idiom is
#     preserved exactly.
#     NOTE: this changes the sound of every effect -- the old
#     recursive accumulation was a low-register thickening that
#     some material wore well. If you want that as a deliberate
#     mode, say the word and it becomes an option.
#   - Verified on 6.4.42 (contrary to review suspicion): bare
#     object[id] with no indices is legal ("same row/col"), so the
#     v1.1 wet/dry mix and pseudo-stereo paths were always
#     functional.
#
# Changelog v1.1:
#   - Fixed selection check syntax
#   - Added wet/dry mix control
#   - Added stereo handling
#   - Added visualization
#   - Preserved all original effect formulas
# ============================================================

form Spectral Effects Suite v1.2
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
    positive Spectral_shift_base: 1.1
    positive Spectral_depth: 0.3
    positive Spectral_cycles: 50
    comment (Cycles for wobble/modulation effects)
    
    comment === AMPLITUDE ENVELOPE ===
    optionmenu Envelope_type: 1
        option Exponential Decay
        option Exponential Crescendo
        option Tremolo with Decay
        option Random Bubbling
        option Turbulent Decay (Gaussian)
        option Rhythmic Pulsing (abs sin)
    positive Envelope_strength: 10
    comment (Higher = stronger effect)
    
    comment === MODULATION ===
    positive Modulation_center: 1.0
    positive Modulation_depth: 0.5
    positive Modulation_cycles: 20
    comment (For tremolo/oscillation/pulsing effects)
    
    comment === MIX ===
    real Wet_dry_percent: 100
    comment (0 = dry, 100 = full wet)
    
    comment === OUTPUT ===
    positive Scale_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_after: 1
endform

# ===================================================================
# SETUP
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")
selectObject: original
original_sr = Get sampling frequency
original_dur = Get total duration
num_channels = Get number of channels

# Handle stereo - keep copy for dry signal
if num_channels > 1
    selectObject: original
    sound = Convert to mono
    selectObject: original
    dry_sound = Convert to mono
else
    selectObject: original
    sound = Copy: "processing"
    selectObject: original
    dry_sound = Copy: "dry"
endif

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

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# ===================================================================
# EFFECT-SPECIFIC ADJUSTMENTS (ORIGINAL LOGIC)
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

writeInfoLine: "=== Spectral Effects Suite v1.2 ==="
appendInfoLine: "Effect: ", effect_name$
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# ===================================================================
# STEP 1: SPECTRAL MANIPULATION (ORIGINAL FORMULAS)
# ===================================================================

# v1.2: freeze the pre-effect signal. The old in-place self[col/f]
# reads returned the just-written output (Formula overwrites left
# to right), making the down-shift term recursive. Both terms now
# read the frozen input, as the symmetric formula intends.
selectObject: sound
frozen = Copy: "frozen_src"
frozId$ = string$(frozen)
selectObject: sound

if effect = 1
    # WOBBLE: Dual frequency modulation (original wobble)
    appendInfoLine: "Applying wobble frequency modulation..."
    Formula: "object[" + frozId$ + ", col/(spectral_shift_base + spectral_depth * sin(spectral_cycles * (x-xmin) / (xmax-xmin)))] - object[" + frozId$ + ", col*(spectral_shift_base + spectral_depth * cos(spectral_cycles * (x-xmin) / (xmax-xmin)))]"
    
elsif effect = 2
    # WOBBLING SHIFT: Single wobble with dual components
    appendInfoLine: "Applying wobbling frequency shift..."
    Formula: "object[" + frozId$ + ", col/(spectral_shift_base + spectral_depth * sin(spectral_cycles * (x-xmin) / (xmax-xmin)))] - object[" + frozId$ + ", col*(spectral_shift_base + spectral_depth * cos(spectral_cycles * (x-xmin) / (xmax-xmin)))]"
    
elsif effect = 3
    # OSCILLATING DECAY: Simple spectral filtering
    appendInfoLine: "Applying spectral filtering..."
    high_factor = spectral_shift_base
    low_factor = spectral_shift_base
    Formula: "object[" + frozId$ + ", col/low_factor] - object[" + frozId$ + ", col*high_factor]"
    
elsif effect = 4
    # UNDERWATER: Multi-band averaging + high freq removal
    appendInfoLine: "Applying underwater muffling..."
    f1 = spectral_shift_base
    f2 = spectral_shift_base + 0.03
    f3 = spectral_shift_base + 0.07
    hf = spectral_shift_base + 0.2
    Formula: "(object[" + frozId$ + ", col/f1] + object[" + frozId$ + ", col/f2] + object[" + frozId$ + ", col/f3]) / 3 - object[" + frozId$ + ", col*hf]"
    
elsif effect = 5
    # REVERSE CRESCENDO: Simple spectral filtering
    appendInfoLine: "Applying spectral filtering..."
    high_factor = spectral_shift_base
    low_factor = spectral_shift_base
    Formula: "object[" + frozId$ + ", col/low_factor] - object[" + frozId$ + ", col*high_factor]"
    
else
    # PULSING REVERSAL: Spectral reversal
    appendInfoLine: "Applying spectral reversal..."
    high_factor = spectral_shift_base
    low_factor = spectral_shift_base
    Formula: "object[" + frozId$ + ", col/low_factor] - object[" + frozId$ + ", col*high_factor]"
endif

removeObject: frozen
selectObject: sound

# ===================================================================
# STEP 2: AMPLITUDE ENVELOPE (ORIGINAL FORMULAS)
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
# WET/DRY MIX
# ===================================================================

if dry_level > 0
    appendInfoLine: "Mixing wet/dry..."
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: sound
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# ===================================================================
# STEREO OUTPUT
# ===================================================================

if num_channels > 1
    selectObject: sound
    mono_result = sound
    
    # Create pseudo-stereo with slight delay difference
    delay_samples = round(0.012 * original_sr)
    delay_str$ = string$(delay_samples)
    mono_str$ = string$(mono_result)
    
    Create Sound from formula: "left", 1, 0, original_dur, original_sr, "object[" + mono_str$ + "]"
    left_ch = selected("Sound")
    
    Create Sound from formula: "right", 1, 0, original_dur, original_sr, 
        ... "if col > " + delay_str$ + " then object[" + mono_str$ + ", col - " + delay_str$ + "] else 0 fi"
    right_ch = selected("Sound")
    
    selectObject: left_ch
    plusObject: right_ch
    sound = Combine to stereo
    
    removeObject: mono_result, left_ch, right_ch
endif

# ===================================================================
# FINALIZE
# ===================================================================

selectObject: sound
appendInfoLine: "Scaling to peak..."
Scale peak: scale_peak

# Rename output
Rename: original_name$ + "_" + effect_name$ + "_" + preset_name$
result = sound

# Cleanup
removeObject: dry_sound

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    # Create spectrum of result for display
    selectObject: result
    if num_channels > 1
        result_mono = Convert to mono
    else
        result_mono = Copy: "result_mono"
    endif
    
    selectObject: result_mono
    result_spectrum = To Spectrum: "yes"
    
    selectObject: original
    if num_channels > 1
        orig_mono = Convert to mono
    else
        orig_mono = Copy: "orig_mono"
    endif
    
    selectObject: orig_mono
    orig_spectrum = To Spectrum: "yes"
    
    # === DRAW ===
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Effects: " + effect_name$ + " (" + preset_name$ + ")"
    
    # --- Original waveform ---
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.4, 3.8, 0.7, 1.7
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Waveform"
    
    # --- Original spectrum ---
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.4, 7.8, 0.7, 1.7
    selectObject: orig_spectrum
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 5000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Spectrum"
    
    # --- Result waveform ---
    Select outer viewport: 0, 4, 2.0, 3.2
    Select inner viewport: 0.4, 3.8, 2.1, 3.1
    selectObject: result
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # --- Result spectrum ---
    Select outer viewport: 4, 8, 2.0, 3.2
    Select inner viewport: 4.4, 7.8, 2.1, 3.1
    selectObject: result_spectrum
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, 5000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Envelope shape ---
    Select outer viewport: 0, 8, 3.4, 4.4
    Select inner viewport: 0.4, 7.6, 3.5, 4.3
    
    # Draw envelope curve
    n_env_points = 200
    env_max = 1.5
    Axes: 0, 1, 0, env_max
    
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, env_max
    
    Colour: "{0.2, 0.7, 0.3}"
    for i from 1 to n_env_points
        t_norm = (i - 1) / (n_env_points - 1)
        
        # Calculate envelope value based on envelope_type
        if envelope_type = 1
            # Exponential Decay
            env_val = envelope_strength^(-t_norm)
        elsif envelope_type = 2
            # Exponential Crescendo
            env_val = envelope_strength^(t_norm - 1)
        elsif envelope_type = 3
            # Tremolo with Decay
            env_val = envelope_strength^(-t_norm) * (modulation_center + modulation_depth * sin(modulation_cycles * t_norm))
        elsif envelope_type = 4
            # Random Bubbling (show average)
            env_val = envelope_strength^(-t_norm) * modulation_center
        elsif envelope_type = 5
            # Turbulent Decay (show average)
            env_val = envelope_strength^(-t_norm) * modulation_center
        else
            # Rhythmic Pulsing
            env_val = abs(sin(modulation_cycles * t_norm)) * envelope_strength^(-t_norm)
        endif
        
        if i > 1
            Draw line: prev_t, prev_env, t_norm, env_val
        endif
        prev_t = t_norm
        prev_env = env_val
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Envelope"
    Text bottom: "yes", "Normalized time (0-1)"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.5, 5.0
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", 
        ... "Shift base: " + fixed$(spectral_shift_base, 2) +
        ... " | Depth: " + fixed$(spectral_depth, 2) +
        ... " | Cycles: " + fixed$(spectral_cycles, 0) +
        ... " | Env: " + fixed$(envelope_strength, 1) +
        ... " | Mod: " + fixed$(modulation_depth, 2) + " @ " + fixed$(modulation_cycles, 0) + " cyc" +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
    
    # Cleanup visualization objects
    removeObject: result_mono, result_spectrum, orig_mono, orig_spectrum
endif

# ===================================================================
# FINAL INFO
# ===================================================================

selectObject: result
result_dur = Get total duration
result_ch = Get number of channels

appendInfoLine: ""
appendInfoLine: "✓ Processing complete!"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", result_ch

if play_after
    selectObject: result
    Play
endif

selectObject: result
