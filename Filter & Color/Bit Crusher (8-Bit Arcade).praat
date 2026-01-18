# ============================================================
# Praat AudioTools - Bit_Crusher__8-Bit_Arcade_.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bit crusher effect for 8-bit arcade sound.
#   Reduces bit depth and sample rate for lo-fi retro effects.
#
# Changelog v0.2:
#   - Fixed preset/mode comparison (number not string)
#   - Fixed Formula variable syntax
#   - Added visualization
#   - Added preset name to output
#   - True stereo processing
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Bit Crusher v0.2
    optionmenu Preset: 1
        option Manual
        option Classic 8-bit
        option Subtle (12-bit)
        option Heavy (4-bit)
        option Extreme (2-bit)
        option Telephone
        option Radio Static
    comment === Processing Mode ===
    optionmenu Mode: 1
        option Time Domain (Fast)
        option Spectral (Experimental)
    comment === Time Domain Parameters ===
    positive Bit_depth 8
    positive Sample_rate_reduction 1
    comment === Spectral Parameters ===
    positive Lower_frequency 200
    positive Upper_frequency 3000
    positive Quantization_steps 2
    real Outside_range_multiplier 0.5
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# Presets (fixed: use number not string)
# ============================================================
if preset = 2
    # Classic 8-bit
    bit_depth = 8
    sample_rate_reduction = 1
    quantization_steps = 2
    presetName$ = "8bit"
elsif preset = 3
    # Subtle (12-bit)
    bit_depth = 12
    sample_rate_reduction = 1
    quantization_steps = 4
    presetName$ = "12bit"
elsif preset = 4
    # Heavy (4-bit)
    bit_depth = 4
    sample_rate_reduction = 2
    quantization_steps = 1
    presetName$ = "4bit"
elsif preset = 5
    # Extreme (2-bit)
    bit_depth = 2
    sample_rate_reduction = 4
    quantization_steps = 1
    presetName$ = "2bit"
elsif preset = 6
    # Telephone
    bit_depth = 8
    sample_rate_reduction = 4
    lower_frequency = 300
    upper_frequency = 3400
    presetName$ = "Telephone"
elsif preset = 7
    # Radio Static
    bit_depth = 6
    sample_rate_reduction = 3
    presetName$ = "RadioStatic"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
clearinfo
writeInfoLine: "=== Bit Crusher v0.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$
appendInfoLine: ""

selectObject: originalSound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# Calculate quantization levels
quant_steps = 2 ^ bit_depth

if mode = 1
    appendInfoLine: "Mode: Time Domain (Fast)"
    appendInfoLine: "Bit depth: ", bit_depth, " (", quant_steps, " levels)"
    appendInfoLine: "Sample rate reduction: ", sample_rate_reduction, "x"
else
    appendInfoLine: "Mode: Spectral (Experimental)"
    appendInfoLine: "Frequency range: ", lower_frequency, " - ", upper_frequency, " Hz"
    appendInfoLine: "Quantization steps: ", quantization_steps
endif
appendInfoLine: ""

# ============================================================
# Processing procedure for single channel
# Returns the processed sound ID via processedSound variable
# ============================================================
procedure processChannel: .inputSound
    selectObject: .inputSound
    .sr = Get sampling frequency
    
    if mode = 1
        # ========================================
        # TIME DOMAIN BIT CRUSHING
        # ========================================
        
        # Apply bit depth reduction
        quant_steps$ = string$(quant_steps)
        Formula: "round(self * " + quant_steps$ + ") / " + quant_steps$
        
        # Apply sample rate reduction if requested
        if sample_rate_reduction > 1
            reduced_sr = .sr / sample_rate_reduction
            Resample: reduced_sr, 50
            .resampled = selected("Sound")
            
            # Resample back up (creates stair-step effect)
            Resample: .sr, 50
            .result = selected("Sound")
            
            # Remove intermediate and original
            removeObject: .resampled, .inputSound
            
            # Return result
            processedSound = .result
        else
            # No resampling, input was modified in place
            processedSound = .inputSound
        endif
        
    else
        # ========================================
        # SPECTRAL QUANTIZATION
        # ========================================
        
        To Spectrum: "yes"
        .spectrum = selected("Spectrum")
        
        # Build formula with modern syntax
        lowF$ = string$(lower_frequency)
        highF$ = string$(upper_frequency)
        qSteps$ = string$(quantization_steps)
        outMult$ = string$(outside_range_multiplier)
        
        Formula: "if x >= " + lowF$ + " and x <= " + highF$ + " then self * (round(" + qSteps$ + " * (x - " + lowF$ + ") / (" + highF$ + " - " + lowF$ + ")) / " + qSteps$ + ") else self * " + outMult$ + " endif"
        
        To Sound
        .result = selected("Sound")
        
        removeObject: .spectrum, .inputSound
        
        processedSound = .result
    endif
    
    selectObject: processedSound
endproc

# ============================================================
# Main processing
# ============================================================
appendInfoLine: "Processing..."

if numChannels = 1
    selectObject: originalSound
    workCopy = Copy: "work_mono"
    @processChannel: workCopy
    finalOutput = processedSound
    
    selectObject: finalOutput
    Rename: originalName$ + "_crushed_" + presetName$
    
else
    # True stereo processing
    selectObject: originalSound
    Extract one channel: 1
    left = selected("Sound")
    
    selectObject: originalSound
    Extract one channel: 2
    right = selected("Sound")
    
    @processChannel: left
    outputLeft = processedSound
    
    @processChannel: right
    outputRight = processedSound
    
    selectObject: outputLeft
    plusObject: outputRight
    Combine to stereo
    finalOutput = selected("Sound")
    Rename: originalName$ + "_crushed_" + presetName$
    
    removeObject: outputLeft, outputRight
endif

selectObject: finalOutput
Scale peak: scale_peak

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Bit Crusher: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.75, 1.9
    selectObject: originalSound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Crushed waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.25, 3.4
    selectObject: finalOutput
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Crushed"
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison (first 50ms)
    zoomEnd = min(0.05, duration)
    
    # Original zoomed
    Select outer viewport: 0, 4, 3.7, 5.2
    Select inner viewport: 0.6, 3.6, 3.9, 5.1
    selectObject: originalSound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, zoomEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Orig"
    Text top: "no", "Zoomed (first 50ms)"
    
    # Crushed zoomed
    Select outer viewport: 4, 8, 3.7, 5.2
    Select inner viewport: 4.4, 7.6, 3.9, 5.1
    selectObject: finalOutput
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, zoomEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Crush"
    Text bottom: "yes", "Time (s)"
    
    # Stats panel
    Select outer viewport: 0, 8, 5.4, 6.5
    Select inner viewport: 0.6, 7.6, 5.5, 6.4
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    
    if mode = 1
        Text: 0.05, "left", 0.7, "half", "Mode: Time Domain"
        Text: 0.05, "left", 0.4, "half", "Bit depth: " + string$(bit_depth) + " (" + string$(quant_steps) + " levels)"
        Text: 0.5, "left", 0.7, "half", "Sample rate reduction: " + string$(sample_rate_reduction) + "x"
        
        # Show effective sample rate
        effectiveSR = round(sampleRate / sample_rate_reduction)
        Text: 0.5, "left", 0.4, "half", "Effective SR: " + string$(effectiveSR) + " Hz"
    else
        Text: 0.05, "left", 0.7, "half", "Mode: Spectral"
        Text: 0.05, "left", 0.4, "half", "Freq range: " + string$(lower_frequency) + "-" + string$(upper_frequency) + " Hz"
        Text: 0.5, "left", 0.7, "half", "Quant steps: " + string$(quantization_steps)
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 10
endif

# ============================================================
# Output
# ============================================================
selectObject: originalSound
plusObject: finalOutput

appendInfoLine: "Done!"
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput