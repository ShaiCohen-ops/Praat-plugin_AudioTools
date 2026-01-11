# ============================================================
# Praat AudioTools - The_Lucier_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   The Lucier Machine - simulates Alvin Lucier's "I Am Sitting
#   in a Room" (1969) via iterative convolution. Creates a
#   physically-modeled room impulse response (direct path +
#   random reflections with RT60 decay) and repeatedly convolves
#   the input with it. Each iteration simulates playing back
#   and re-recording in the room. Room resonances accumulate,
#   gradually transforming speech into tonal frequencies.
#
# Changelog v0.2:
#   - Added presets
#   - Fixed variable naming
#   - Added visualization
#   - Better progress feedback
# ============================================================

form The Lucier Machine
    comment Select a Sound object first (speech recommended)
    
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Classic Lucier (30 iterations)
        option Quick Preview (10 iterations)
        option Extended Transformation (50 iterations)
        option Small Room (short RT60)
        option Large Hall (long RT60)
    
    comment === Room Acoustics ===
    positive IR_duration_s 1.5
    positive RT60_s 1.0
    natural Number_of_reflections 1000
    
    comment === Microphone Placement ===
    positive Pre_delay_s 0.01
    real Mic_proximity_gain 0.92
    comment (0.95-0.99 = close mic, slow change)
    comment (0.70-0.90 = far mic, fast change)
    
    comment === Simulation ===
    natural Number_of_iterations 30
    positive Normalization_level 0.99
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Classic Lucier
    iR_duration_s = 1.5
    rT60_s = 1.0
    number_of_reflections = 1000
    pre_delay_s = 0.01
    mic_proximity_gain = 0.92
    number_of_iterations = 30
    presetName$ = "Classic"
elsif preset = 3
    # Quick Preview
    iR_duration_s = 1.0
    rT60_s = 0.8
    number_of_reflections = 500
    pre_delay_s = 0.01
    mic_proximity_gain = 0.88
    number_of_iterations = 10
    presetName$ = "Quick"
elsif preset = 4
    # Extended Transformation
    iR_duration_s = 2.0
    rT60_s = 1.2
    number_of_reflections = 1500
    pre_delay_s = 0.012
    mic_proximity_gain = 0.94
    number_of_iterations = 50
    presetName$ = "Extended"
elsif preset = 5
    # Small Room
    iR_duration_s = 0.8
    rT60_s = 0.4
    number_of_reflections = 600
    pre_delay_s = 0.005
    mic_proximity_gain = 0.90
    number_of_iterations = 30
    presetName$ = "SmallRoom"
elsif preset = 6
    # Large Hall
    iR_duration_s = 3.0
    rT60_s = 2.5
    number_of_reflections = 2000
    pre_delay_s = 0.025
    mic_proximity_gain = 0.85
    number_of_iterations = 30
    presetName$ = "LargeHall"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== The Lucier Machine ==="
appendInfoLine: "Simulating 'I Am Sitting in a Room'"
appendInfoLine: ""
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Room parameters:"
appendInfoLine: "  IR duration: ", iR_duration_s, " s"
appendInfoLine: "  RT60: ", rT60_s, " s"
appendInfoLine: "  Reflections: ", number_of_reflections
appendInfoLine: "  Pre-delay: ", pre_delay_s * 1000, " ms"
appendInfoLine: ""
appendInfoLine: "Microphone placement:"
appendInfoLine: "  Proximity gain: ", mic_proximity_gain
appendInfoLine: "  Direct path: ", fixed$(mic_proximity_gain * 100, 1), "%"
appendInfoLine: "  Room reflections: ", fixed$((1 - mic_proximity_gain) * 100, 1), "%"
appendInfoLine: ""
appendInfoLine: "Simulation:"
appendInfoLine: "  Iterations: ", number_of_iterations
appendInfoLine: ""

# ============================================================
# GENERATE IMPULSE RESPONSE
# ============================================================

appendInfoLine: "Generating impulse response..."

# Create empty IR
Create Sound from formula: "IR", 1, 0, iR_duration_s, sr, "0"
irSound = selected("Sound")
totalSamples = Get number of samples

# Direct path (mic proximity)
directSample = round(pre_delay_s * sr)
if directSample < 1
    directSample = 1
endif
if directSample <= totalSamples
    Set value at sample number: 1, directSample, mic_proximity_gain
endif

# Reflections with RT60 decay
decayCoeff = 6.9078 / rT60_s
reflectionMaxAmp = 1.0 - mic_proximity_gain
if reflectionMaxAmp < 0.05
    reflectionMaxAmp = 0.05
endif

for i from 1 to number_of_reflections
    # Random time after direct sound
    randTime = pre_delay_s + randomUniform(0, iR_duration_s - pre_delay_s)
    
    # Exponential decay
    timeDelta = randTime - pre_delay_s
    naturalDecay = exp(-timeDelta * decayCoeff)
    
    # Random amplitude with decay
    amp = randomGauss(0, 0.3) * naturalDecay * reflectionMaxAmp
    
    # Place in IR
    sampIdx = round(randTime * sr)
    if sampIdx >= 1 and sampIdx <= totalSamples
        oldVal = Get value at sample number: 1, sampIdx
        Set value at sample number: 1, sampIdx, oldVal + amp
    endif
endfor

selectObject: irSound
Scale peak: 0.9

appendInfoLine: "  IR generated successfully."
appendInfoLine: ""

# Store peak values for visualization
for iter from 0 to number_of_iterations
    peakHistory[iter] = 0
endfor

# ============================================================
# ITERATIVE CONVOLUTION
# ============================================================

appendInfoLine: "Starting iterative convolution..."
appendInfoLine: ""

# Convert to mono if stereo
selectObject: original
if numChannels = 2
    Convert to mono
    currentSound = selected("Sound")
else
    Copy: originalName$ + "_iteration_0"
    currentSound = selected("Sound")
endif

peakHistory[0] = 1.0

for iteration from 1 to number_of_iterations
    # Progress
    appendInfoLine: "  Iteration ", iteration, " / ", number_of_iterations
    
    # Convolve with IR
    selectObject: currentSound, irSound
    Convolve: "sum", "zero"
    convolved = selected("Sound")
    
    # Crop to original duration
    selectObject: convolved
    Extract part: 0, originalDur, "rectangular", 1, "no"
    cropped = selected("Sound")
    
    # Cleanup
    removeObject: currentSound, convolved
    
    # Normalize
    selectObject: cropped
    Scale peak: normalization_level
    
    # Store peak for visualization
    currentPeak = Get absolute extremum: 0, 0, "None"
    peakHistory[iteration] = currentPeak
    
    # Rename
    Rename: originalName$ + "_iteration_" + string$(iteration)
    currentSound = selected("Sound")
endfor

result = currentSound
Rename: originalName$ + "_lucier_" + presetName$

# Cleanup IR
removeObject: irSound

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "The Lucier Machine: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.7, 1.7
    Select inner viewport: 0.5, 3.7, 0.85, 1.55
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Original"
    Text bottom: "yes", "Time (s)"
    
    # Result waveform
    Select outer viewport: 4, 8, 0.7, 1.7
    Select inner viewport: 4.5, 7.7, 0.85, 1.55
    selectObject: result
    Colour: "{0.7, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "After " + string$(number_of_iterations) + " iterations"
    Text bottom: "yes", "Time (s)"
    
    # Iteration diagram
    Select outer viewport: 0, 8, 1.9, 3.5
    Select inner viewport: 0.6, 7.6, 2.1, 3.35
    
    Axes: 0, number_of_iterations, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, number_of_iterations, 0, 1.1
    
    # Draw iteration boxes
    boxWidth = number_of_iterations / 20
    if boxWidth < 1
        boxWidth = 1
    endif
    
    # Show every Nth iteration to avoid clutter
    step = 1
    if number_of_iterations > 30
        step = round(number_of_iterations / 20)
    endif
    
    iter = 0
    while iter <= number_of_iterations
        # Color gradient from blue (original) to red (final)
        ratio = iter / number_of_iterations
        r = 0.4 + 0.4 * ratio
        g = 0.5 - 0.2 * ratio
        b = 0.8 - 0.4 * ratio
        col$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        Colour: col$
        Paint rectangle: col$, iter - boxWidth * 0.4, iter + boxWidth * 0.4, 0, 0.9
        
        iter = iter + step
    endwhile
    
    # Arrow showing transformation
    Colour: "{0.3, 0.3, 0.3}"
    Arrow size: 1.5
    Draw arrow: 1, 0.5, number_of_iterations - 1, 0.5
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Transform"
    Text bottom: "yes", "Iteration"
    
    # Labels
    Font size: 5
    Colour: "{0.4, 0.5, 0.8}"
    Text: 2, "centre", 1.0, "half", "Speech"
    Colour: "{0.8, 0.4, 0.4}"
    Text: number_of_iterations - 2, "centre", 1.0, "half", "Resonance"
    
    # Parameters panel
    Select outer viewport: 0, 8, 3.6, 4.3
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.8, "half", "Room: RT60=" + fixed$(rT60_s, 1) + "s, " + string$(number_of_reflections) + " reflections | Mic proximity: " + fixed$(mic_proximity_gain, 2) + " | Iterations: " + string$(number_of_iterations)
    
    # Lucier quote
    Font size: 6
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.5, "centre", 0.3, "half", """I am sitting in a room different from the one you are in now..."""
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Final duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
appendInfoLine: ""
appendInfoLine: "TIPS:"
appendInfoLine: "  • Speech fades too quickly? Increase proximity (0.97-0.99)"
appendInfoLine: "  • Effect too subtle? Decrease proximity (0.85-0.90)"
appendInfoLine: "  • Classic Lucier: proximity 0.90-0.92, 25-30 iterations"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
