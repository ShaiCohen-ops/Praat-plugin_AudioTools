# ============================================================
# Praat AudioTools - Even-Odd_Harmonic_Binaural_Separation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Separates even and odd harmonics into different stereo channels
#   for binaural listening effect.
#
# Changelog v0.3:
#   - Added presets for different separation modes
#   - Added visualization
#   - Added play toggle
#   - Removed goto statements
# ============================================================

form Even-Odd Harmonic Binaural Separation
    comment === PRESET ===
    optionmenu Preset: 1
        option: "1. Odd Left / Even Right"
        option: "2. Even Left / Odd Right"
        option: "3. Odd Only (mono)"
        option: "4. Even Only (mono)"
        option: "5. Custom F0"
    
    comment === F0 Detection ===
    boolean Auto_detect_F0 1
    positive Manual_F0_Hz 100
    
    comment === Filter Settings ===
    positive Maximum_frequency 5000
    positive Filter_width_factor 0.4
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
duration = Get total duration
sr = Get sampling frequency

# === Preset names ===
if preset = 1
    presetName$ = "OddL_EvenR"
elsif preset = 2
    presetName$ = "EvenL_OddR"
elsif preset = 3
    presetName$ = "OddOnly"
elsif preset = 4
    presetName$ = "EvenOnly"
else
    presetName$ = "Custom"
endif

# === Make working copy ===
selectObject: sound
workCopy = Copy: "working"

# === Auto-detect F0 ===
if auto_detect_F0
    selectObject: workCopy
    pitch = To Pitch: 0.01, 75, 600
    f0 = Get mean: 0, 0, "Hertz"
    if f0 = undefined
        f0 = manual_F0_Hz
        appendInfoLine: "Warning: Could not detect F0, using: ", f0, " Hz"
    endif
    removeObject: pitch
else
    f0 = manual_F0_Hz
endif

# === Info ===
writeInfoLine: "=== Even-Odd Harmonic Binaural Separation ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "F0: ", fixed$(f0, 2), " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# === Calculate parameters ===
rejectWidth = f0 * filter_width_factor
maxHarmonic = floor(maximum_frequency / f0)

appendInfoLine: "Notch width: ±", fixed$(rejectWidth, 1), " Hz"
appendInfoLine: "Processing up to harmonic ", maxHarmonic
appendInfoLine: ""

# === Create ODD harmonics (remove EVEN) ===
if preset <> 4
    appendInfoLine: "Creating odd harmonics (removing even)..."
    selectObject: workCopy
    oddSound = Copy: "odd_temp"
    
    harmonic = 2
    keepProcessingOdd = 1
    while harmonic <= maxHarmonic and keepProcessingOdd = 1
        freq = harmonic * f0
        
        if freq > sr/2 - 200
            keepProcessingOdd = 0
        else
            lowFreq = max(5, freq - rejectWidth)
            highFreq = freq + rejectWidth
            
            selectObject: oddSound
            filtered = Filter (stop Hann band): lowFreq, highFreq, 100
            removeObject: oddSound
            oddSound = filtered
            
            harmonic = harmonic + 2
        endif
    endwhile
    
    selectObject: oddSound
    Scale peak: 0.95
endif

# === Create EVEN harmonics (remove ODD) ===
if preset <> 3
    appendInfoLine: "Creating even harmonics (removing odd)..."
    selectObject: workCopy
    evenSound = Copy: "even_temp"
    
    harmonic = 1
    keepProcessingEven = 1
    while harmonic <= maxHarmonic and keepProcessingEven = 1
        freq = harmonic * f0
        
        if freq > sr/2 - 200
            keepProcessingEven = 0
        else
            lowFreq = max(5, freq - rejectWidth)
            highFreq = freq + rejectWidth
            
            selectObject: evenSound
            filtered = Filter (stop Hann band): lowFreq, highFreq, 100
            removeObject: evenSound
            evenSound = filtered
            
            harmonic = harmonic + 2
        endif
    endwhile
    
    selectObject: evenSound
    Scale peak: 0.95
endif

# === Create output based on preset ===
if preset = 1
    # Odd Left / Even Right
    selectObject: oddSound, evenSound
    result = Combine to stereo
    removeObject: oddSound, evenSound
    leftLabel$ = "Odd (1,3,5...)"
    rightLabel$ = "Even (2,4,6...)"
elsif preset = 2
    # Even Left / Odd Right
    selectObject: evenSound, oddSound
    result = Combine to stereo
    removeObject: oddSound, evenSound
    leftLabel$ = "Even (2,4,6...)"
    rightLabel$ = "Odd (1,3,5...)"
elsif preset = 3
    # Odd Only (mono to stereo)
    selectObject: oddSound
    result = Convert to stereo
    removeObject: oddSound
    leftLabel$ = "Odd"
    rightLabel$ = "Odd"
elsif preset = 4
    # Even Only (mono to stereo)
    selectObject: evenSound
    result = Convert to stereo
    removeObject: evenSound
    leftLabel$ = "Even"
    rightLabel$ = "Even"
else
    # Custom (same as preset 1)
    selectObject: oddSound, evenSound
    result = Combine to stereo
    removeObject: oddSound, evenSound
    leftLabel$ = "Odd"
    rightLabel$ = "Even"
endif

selectObject: result
Rename: soundName$ + "_binaural_" + presetName$

# === Cleanup ===
removeObject: workCopy

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Harmonic Separation: " + presetName$ + " | F0=" + fixed$(f0, 1) + "Hz | " + soundName$
    
    # Harmonic diagram
    Select outer viewport: 0.5, 9.5, 0.8, 3.0
    Select inner viewport: 0.8, 9.2, 1.1, 2.7
    
    maxFreqDisplay = min(maximum_frequency, 2000)
    Axes: 0, maxFreqDisplay, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxFreqDisplay, -1.5, 1.5
    
    # Center line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, maxFreqDisplay, 0
    Solid line
    
    # Draw harmonics
    for h from 1 to maxHarmonic
        freq = h * f0
        if freq <= maxFreqDisplay
            isOdd = (h mod 2) = 1
            
            if isOdd
                # Odd harmonics - top (left channel for preset 1)
                if preset = 1 or preset = 3 or preset = 5
                    Paint rectangle: "{0.3, 0.5, 0.8}", freq - 15, freq + 15, 0.1, 1.2
                else
                    Paint rectangle: "{0.3, 0.5, 0.8}", freq - 15, freq + 15, -1.2, -0.1
                endif
            else
                # Even harmonics - bottom (right channel for preset 1)
                if preset = 1 or preset = 5
                    Paint rectangle: "{0.8, 0.5, 0.3}", freq - 15, freq + 15, -1.2, -0.1
                elsif preset = 2
                    Paint rectangle: "{0.8, 0.5, 0.3}", freq - 15, freq + 15, 0.1, 1.2
                elsif preset = 4
                    Paint rectangle: "{0.8, 0.5, 0.3}", freq - 15, freq + 15, 0.1, 1.2
                endif
            endif
            
            # Label
            Font size: 5
            Colour: "Black"
            Text: freq, "centre", 1.35, "half", string$(h)
        endif
    endfor
    
    # Labels
    Font size: 7
    Colour: "{0.3, 0.5, 0.8}"
    Text: maxFreqDisplay * 0.02, "left", 0.7, "half", "LEFT: " + leftLabel$
    Colour: "{0.8, 0.5, 0.3}"
    Text: maxFreqDisplay * 0.02, "left", -0.7, "half", "RIGHT: " + rightLabel$
    
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 200, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Harmonic Distribution (numbers = harmonic #)"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 3.2, 5.0
    Select inner viewport: 0.8, 9.2, 3.4, 4.8
    selectObject: result
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "  Left:  ", leftLabel$
appendInfoLine: "  Right: ", rightLabel$
appendInfoLine: ""
appendInfoLine: "Listen with headphones for binaural effect!"

if play_result
    selectObject: result
    Play
endif

selectObject: result
