# ============================================================
# Praat AudioTools - Bit Crusher (8-Bit Arcade).praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Bit Crusher (Time Domain)
    comment This script applies bit-depth reduction for 8-bit arcade sound
    optionmenu Preset: 1
        option Default (8-bit)
        option Subtle (12-bit)
        option Heavy (4-bit)
        option Extreme (2-bit)
    comment Processing mode:
    optionmenu Mode: 1
        option Time Domain (Fast - Classic Bit Crusher)
        option Spectral (Slow - Experimental Metallic Sound)
    comment ==========================================
    comment TIME DOMAIN PARAMETERS (Fast Mode):
    comment ==========================================
    positive bit_depth 8
    comment (bit depth: 1-16, lower = more crushed)
    positive sample_rate_reduction 1
    comment (1 = no reduction, 2 = half rate, 4 = quarter rate, etc.)
    comment ==========================================
    comment SPECTRAL PARAMETERS (Slow Mode Only):
    comment ==========================================
    boolean fast_fourier yes
    comment (use "yes" for faster FFT processing)
    positive lower_frequency 200
    positive upper_frequency 3000
    positive quantization_steps 2
    positive outside_range_multiplier 0.5
    comment ==========================================
    comment OUTPUT OPTIONS:
    comment ==========================================
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Apply preset values
if preset$ = "Subtle (12-bit)"
    bit_depth = 12
    sample_rate_reduction = 1
    quantization_steps = 4
elif preset$ = "Heavy (4-bit)"
    bit_depth = 4
    sample_rate_reduction = 2
    quantization_steps = 1
elif preset$ = "Extreme (2-bit)"
    bit_depth = 2
    sample_rate_reduction = 4
    quantization_steps = 1
endif

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound name
originalName$ = selected$("Sound")
originalSound = selected("Sound")

# ============================================================
# PROCESSING MODE SELECTION
# ============================================================

if mode$ = "Time Domain (Fast - Classic Bit Crusher)"
    # ========================================
    # TIME DOMAIN BIT CRUSHING (FAST)
    # ========================================
    
    # Calculate quantization levels
    quant_steps = 2 ^ bit_depth
    
    # Create a copy to work with
    selectObject: originalSound
    result = Copy: originalName$ + "_bitcrushed"
    
    # Apply bit depth reduction (amplitude quantization)
    Formula: "round(self * quant_steps) / quant_steps"
    
    # Apply sample rate reduction if requested
    if sample_rate_reduction > 1
        # Get current sample rate
        original_sr = Get sampling frequency
        
        # Resample down
        reduced_sr = original_sr / sample_rate_reduction
        Resample: reduced_sr, 50
        
        # Resample back up (creates stair-step effect)
        Resample: original_sr, 50
    endif
    
else
    # ========================================
    # SPECTRAL QUANTIZATION (SLOW)
    # ========================================
    
    writeInfoLine: "WARNING: Spectral mode selected. This may take longer to process."
    appendInfoLine: "For faster processing, use Time Domain mode."
    
    # Convert to spectrum
    selectObject: originalSound
    spectrum = To Spectrum: fast_fourier
    
    # Apply spectral quantization
    Formula: "if x >= 'lower_frequency' and x <= 'upper_frequency' then self * (round('quantization_steps' * (x - 'lower_frequency') / ('upper_frequency' - 'lower_frequency')) / 'quantization_steps') else self * 'outside_range_multiplier' fi"
    
    # Convert back to sound
    result = To Sound
    
    # Rename result
    Rename: originalName$ + "_spectral_quantized"
    
    # Clean up spectrum if not keeping intermediate objects
    if not keep_intermediate_objects
        selectObject: spectrum
        Remove
    endif
endif

# ============================================================
# POST-PROCESSING (BOTH MODES)
# ============================================================

# Select the result
selectObject: result

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif

# Display processing info
selectObject: result
duration = Get total duration
writeInfoLine: "Bit Crushing Complete"
appendInfoLine: "Mode: ", mode$
if mode$ = "Time Domain (Fast - Classic Bit Crusher)"
    appendInfoLine: "Bit Depth: ", bit_depth, " bits (", quant_steps, " levels)"
    appendInfoLine: "Sample Rate Reduction: ", sample_rate_reduction, "x"
else
    appendInfoLine: "Frequency Range: ", lower_frequency, " - ", upper_frequency, " Hz"
    appendInfoLine: "Quantization Steps: ", quantization_steps
endif
appendInfoLine: "Duration: ", fixed$(duration, 2), " seconds"
appendInfoLine: "Result: ", selected$("Sound")