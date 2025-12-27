# ============================================================
# Praat AudioTools - Jitter-Shimmer Formant Mapping.praat
# Author: Shai Cohen
# Version: 1.2 (2025) - Safe Logic (No Unit Assumptions)
# License: MIT License
#
# Description:
#   Maps voice perturbation (jitter/shimmer) to timbral transformation.
#   
#   v1.2 Fix:
#   - Removed "magic number" unit conversion. 
#   - Treats all inputs as raw percentages from Voice Report.
#   - Preserves dynamic range: Low jitter = Low effect.
# ============================================================

form Jitter Shimmer to Formant Mapping
    comment === PRESETS ===
    optionmenu Preset 1
        option Modal (Subtle)
        option Breathy (Brighter, Higher Pitch)
        option Creaky (Darker, Lower Pitch)
        option Robot (Monotone, Extreme)
        option Custom
    
    comment --- Intensity (Global Multiplier) ---
    positive intensity_multiplier 1.0
    
    comment --- Mapping Sensitivity (Weight per 1% perturbation) ---
    # Meaning: A value of 0.1 means 1% jitter adds 0.1 to the formant ratio.
    real jitter_Weight 0.1
    real shimmer_Weight 0.1
    
    comment --- Output Options ---
    boolean play_result 1
    boolean keep_intermediates 0
endform

# ============================================================
# INITIALIZATION
# ============================================================

clearinfo
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║      JITTER/SHIMMER MAPPING v1.2 (Dynamic Range Fix)         ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"

if numberOfSelected("Sound") = 0
    exitScript: "ERROR: Please select one or more Sound objects first."
endif

number_of_sounds = numberOfSelected("Sound")
for i from 1 to number_of_sounds
    sound[i] = selected("Sound", i)
endfor

# ============================================================
# PRESET CONFIGURATION
# ============================================================

# Default Base values
pitch_multiplier = 1.0
pitch_range_factor = 1.0

# Load params from form into local variables
j_weight = jitter_Weight
s_weight = shimmer_Weight

if preset = 1
    # Modal: Very subtle enhancement
    j_weight = 0.05
    s_weight = 0.05
    pitch_multiplier = 1.0
    preset_name$ = "Modal"
elsif preset = 2
    # Breathy: Needs high sensitivity to catch subtle breathiness
    j_weight = 0.3
    s_weight = 0.2
    pitch_multiplier = 1.15
    preset_name$ = "Breathy"
elsif preset = 3
    # Creaky: Negative weights to darken the sound
    j_weight = -0.3
    s_weight = -0.1
    pitch_multiplier = 0.85
    preset_name$ = "Creaky"
elsif preset = 4
    # Robot: Extreme sensitivity, flattens pitch
    j_weight = 1.0
    s_weight = 0.5
    pitch_multiplier = 1.0
    pitch_range_factor = 0.0
    preset_name$ = "Robot"
else
    preset_name$ = "Custom"
endif

appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Intensity: ", intensity_multiplier, "x"

# ============================================================
# MAIN LOOP
# ============================================================

for current from 1 to number_of_sounds
    
    selectObject: sound[current]
    
    # 1. CAPTURE ORIGINAL NAME & HANDLE MONO
    original_name$ = selected$("Sound")
    num_channels = Get number of channels
    
    is_temp_mono = 0
    if num_channels > 1
        Convert to mono
        working_sound = selected("Sound")
        Rename: original_name$ + "_temp_mono"
        is_temp_mono = 1
    else
        working_sound = sound[current]
    endif
    
    # ------------------------------------------------
    # 2. ANALYSIS
    # ------------------------------------------------
    selectObject: working_sound
    
    # Pitch analysis (needed for median pitch)
    pitch = To Pitch (cc): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
    original_median_pitch = Get quantile: 0, 0, 0.5, "Hertz"
    if original_median_pitch = undefined
        original_median_pitch = 150
    endif
    
    # Voice Report (Jitter/Shimmer)
    selectObject: working_sound
    plusObject: pitch
    point_process = To PointProcess (cc)
    
    selectObject: working_sound
    plusObject: pitch
    plusObject: point_process
    voice_report$ = Voice report: 0, 0, 75, 600, 1.3, 1.6, 0.03, 0.45
    
    # Extract Raw Numbers (Praat standardly returns %)
    # Example: "Jitter (local): 0.234%" -> returns 0.234
    jitter_val = extractNumber(voice_report$, "Jitter (local): ")
    shimmer_val = extractNumber(voice_report$, "Shimmer (local): ")
    
    # Defaults/Safety for silence/errors
    if jitter_val = undefined
        jitter_val = 0.0
    endif
    if shimmer_val = undefined
        shimmer_val = 0.0
    endif
    
    # NOTE: REMOVED THE "IF < 0.5 THEN *100" BLOCK
    # We now trust the values are correct relative to each other.
    # Clean voice = 0.2, Rough voice = 2.0.

    # ------------------------------------------------
    # 3. COMPOSITE SCALING LOGIC
    # ------------------------------------------------
    
    # Apply Intensity (User control)
    eff_jitter = jitter_val * intensity_multiplier
    eff_shimmer = shimmer_val * intensity_multiplier
    
    # Calculate Influences (Linear Mapping)
    # Formula: 1.0 + (Percent_Value * Sensitivity_Weight)
    # Example Clean: 1.0 + (0.2 * 0.3) = 1.06 (Subtle)
    # Example Rough: 1.0 + (2.0 * 0.3) = 1.60 (Extreme)
    
    jitter_influence = 1.0 + (eff_jitter * j_weight)
    shimmer_influence = 1.0 + (eff_shimmer * s_weight)
    
    # Average into Global Ratio
    composite_ratio = (jitter_influence + shimmer_influence) / 2
    
    # Clamp (Safety limits)
    composite_ratio = max(0.6, min(2.0, composite_ratio))
    
    # Target Pitch
    target_pitch = original_median_pitch * pitch_multiplier
    
    appendInfoLine: "------------------------------------------------"
    appendInfoLine: "Sound: ", original_name$
    appendInfoLine: "  Input Jitter: ", fixed$(jitter_val, 3), "% | Shimmer: ", fixed$(shimmer_val, 3), "%"
    appendInfoLine: "  => Calculated Scale: x", fixed$(composite_ratio, 3)
    appendInfoLine: "  => Pitch Shift: ", fixed$(original_median_pitch, 0), "Hz -> ", fixed$(target_pitch, 0), "Hz"

    # ------------------------------------------------
    # 4. RESYNTHESIS
    # ------------------------------------------------
    selectObject: working_sound
    
    # Change gender (PSOLA global scaling)
    result_sound = Change gender: 75, 600, composite_ratio, target_pitch, pitch_range_factor, 1
    
    selectObject: result_sound
    Scale peak: 0.95
    Rename: original_name$ + "_" + preset_name$
    result_id = selected("Sound")
    
    # ------------------------------------------------
    # 5. CLEANUP & PLAYBACK
    # ------------------------------------------------
    
    if not keep_intermediates
        removeObject: pitch, point_process
    endif
    
    if is_temp_mono
        removeObject: working_sound
    endif
    
    if play_result
        selectObject: result_id
        Play
    endif

endfor

appendInfoLine: "Done."

# ============================================================
# HELPER
# ============================================================

procedure extractNumber: .text$, .label$
    .index = index(.text$, .label$)
    if .index = 0
        .return = undefined
    else
        .length = length(.label$)
        .start = .index + .length
        .rest$ = mid$(.text$, .start, 30)
        .return = extractNumber(.rest$, "")
        if .return = undefined
             .end = index(.rest$, " ")
             if .end = 0
                 .end = index(.rest$, newline$)
             endif
             if .end > 0
                 .val$ = left$(.rest$, .end - 1)
                 .return = number(.val$)
             endif
        endif
    endif
endproc