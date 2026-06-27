# ============================================================
# Praat AudioTools - Pitch_Stylization_and_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Stylization and Shift - combines pitch smoothing,
#   transposition, quantization (auto-tune), and monotone
#   (robot voice) effects. Quick tool for common pitch edits.
#   Note: the Robot preset flattens to the mean AND drops it by
#   2 semitones for a lower, machine-like timbre.
#
# Changelog v0.3:
#   - Fixed off-screen pitch-panel legend (now in Hz/time coords)
#   - Standard header
#   - Documented Robot preset's -2 st drop
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
orig_name$ = selected$("Sound")

selectObject: original
dur = Get total duration
fs = Get sampling frequency

# === Form ===
form Pitch Stylization and Shift
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (use settings below)
        option Gentle Smoothing
        option Stepwise Quantize (Auto-tune)
        option Robot Voice (Monotone)
        option Pitch Down (-1 Octave)
        option Pitch Up (+1 Octave)
        option Strong Stylize
    
    comment === Manual Parameters ===
    real Stylize_Hz 2
    real Shift_semitones 0
    
    comment === Analysis ===
    positive Time_step 0.005
    positive Min_pitch 75
    positive Max_pitch 600
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
op_stylize = stylize_Hz
op_shift = shift_semitones
mode = 0
# mode: 0=Normal, 1=Quantize, 2=Robot

if preset = 2
    # Gentle Smoothing
    op_stylize = 3.0
    op_shift = 0
    mode = 0
    presetName$ = "Gentle"
elsif preset = 3
    # Stepwise Quantize
    op_stylize = 0
    op_shift = 0
    mode = 1
    presetName$ = "Quantize"
elsif preset = 4
    # Robot Voice
    op_stylize = 0
    op_shift = -2
    mode = 2
    presetName$ = "Robot"
elsif preset = 5
    # Pitch Down
    op_stylize = 0
    op_shift = -12
    mode = 0
    presetName$ = "Octave-"
elsif preset = 6
    # Pitch Up
    op_stylize = 0
    op_shift = 12
    mode = 0
    presetName$ = "Octave+"
elsif preset = 7
    # Strong Stylize
    op_stylize = 10.0
    op_shift = -5
    mode = 0
    presetName$ = "Strong"
else
    presetName$ = "Manual"
endif

# Get mode name
if mode = 0
    modeName$ = "Normal"
elsif mode = 1
    modeName$ = "Quantize"
else
    modeName$ = "Robot"
endif

# === Info ===
writeInfoLine: "=== Pitch Stylization and Shift ==="
appendInfoLine: "Source: ", orig_name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
if op_stylize > 0
    appendInfoLine: "Stylize: ", op_stylize, " Hz"
endif
if op_shift <> 0
    appendInfoLine: "Shift: ", op_shift, " semitones"
endif
appendInfoLine: ""

# === Create Manipulation ===
appendInfoLine: "Analyzing pitch..."
selectObject: original
manipulation = To Manipulation: time_step, min_pitch, max_pitch

selectObject: manipulation
pitchTier = Extract pitch tier

# Store original for visualization
selectObject: pitchTier
origPitchTier = Copy: "original_pitch"

# === Apply Effects Based on Mode ===
selectObject: pitchTier

if mode = 2
    # ROBOT: Flatten to mean pitch
    appendInfoLine: "Flattening to monotone..."
    mean_val = Get mean (curve): 0, 0
    Formula: ~ mean_val
    appendInfoLine: "Mean pitch: ", fixed$(mean_val, 1), " Hz"

elsif mode = 1
    # QUANTIZE: Snap to nearest semitone
    appendInfoLine: "Quantizing to semitones..."
    Formula: ~ 440 * 2 ^ (round(12 * log2(self / 440)) / 12)

else
    # NORMAL: Stylize
    if op_stylize > 0
        appendInfoLine: "Stylizing pitch contour..."
        Stylize: op_stylize, "Hz"
    endif
endif

# === Apply Shift ===
if op_shift <> 0
    appendInfoLine: "Shifting by ", op_shift, " semitones..."
    selectObject: pitchTier
    Shift frequencies: 0, dur, op_shift, "semitones"
endif

# === Resynthesize ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

selectObject: manipulation, pitchTier
Replace pitch tier

selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: orig_name$ + "_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Pitch Stylization & Shift##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", orig_name$ + " | " + presetName$ + " | " + modeName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    if mode = 2
        Colour: "{0.7, 0.5, 0.6}"
    elsif mode = 1
        Colour: "{0.5, 0.6, 0.7}"
    else
        Colour: "{0.5, 0.7, 0.6}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", presetName$
    Text bottom: "yes", "Time (s)"
    
    # Pitch comparison
    Select outer viewport: 0, 8, 2.7, 4.5
    Select inner viewport: 0.6, 7.6, 2.9, 4.4
    
    # Get pitch range from original tier
    selectObject: origPitchTier
    nPts = Get number of points
    
    if nPts > 0
        minP = 1000
        maxP = 50
        
        for pt from 1 to nPts
            selectObject: origPitchTier
            f = Get value at index: pt
            if f > 0
                if f < minP
                    minP = f
                endif
                if f > maxP
                    maxP = f
                endif
            endif
        endfor
        
        selectObject: pitchTier
        nPts2 = Get number of points
        for pt from 1 to nPts2
            f = Get value at index: pt
            if f > 0
                if f < minP
                    minP = f
                endif
                if f > maxP
                    maxP = f
                endif
            endif
        endfor
        
        pMargin = (maxP - minP) * 0.15
        if pMargin < 20
            pMargin = 20
        endif
        
        Axes: 0, dur, minP - pMargin, maxP + pMargin
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, dur, minP - pMargin, maxP + pMargin
        
        # Draw original pitch
        Colour: "{0.7, 0.7, 0.7}"
        selectObject: origPitchTier
        for pt from 2 to nPts
            t1 = Get time from index: pt - 1
            t2 = Get time from index: pt
            f1 = Get value at index: pt - 1
            f2 = Get value at index: pt
            if f1 > 0 and f2 > 0
                Draw line: t1, f1, t2, f2
            endif
        endfor
        
        # Draw processed pitch
        if mode = 2
            Colour: "{0.7, 0.4, 0.5}"
        elsif mode = 1
            Colour: "{0.4, 0.5, 0.7}"
        else
            Colour: "{0.4, 0.7, 0.5}"
        endif
        Line width: 1.5
        selectObject: pitchTier
        for pt from 2 to nPts2
            t1 = Get time from index: pt - 1
            t2 = Get time from index: pt
            f1 = Get value at index: pt - 1
            f2 = Get value at index: pt
            if f1 > 0 and f2 > 0
                Draw line: t1, f1, t2, f2
            endif
        endfor
        Line width: 1
        
        # Draw semitone grid for quantize mode
        if mode = 1
            Colour: "{0.85, 0.85, 0.95}"
            minMidi = floor(69 + 12 * log2(minP / 440))
            maxMidi = ceiling(69 + 12 * log2(maxP / 440))
            for midi from minMidi to maxMidi
                freq = 440 * (2 ^ ((midi - 69) / 12))
                Dotted line
                Draw line: 0, freq, dur, freq
                Solid line
            endfor
        endif
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Pitch (Hz)"
        Text bottom: "yes", "Time (s)"
        
        # Legend (panel's own Hz/time coordinates, near the top)
        legY = maxP + pMargin * 0.5
        legX = dur * 0.03
        Font size: 6
        Colour: "{0.7, 0.7, 0.7}"
        Text: legX, "left", legY, "half", "Original"
        if mode = 2
            Colour: "{0.7, 0.4, 0.5}"
        elsif mode = 1
            Colour: "{0.4, 0.5, 0.7}"
        else
            Colour: "{0.4, 0.7, 0.5}"
        endif
        Text: legX + dur * 0.14, "left", legY, "half", "Processed"
    endif
    
    # Mode indicator
    Select outer viewport: 0, 8, 4.7, 5.3
    Select inner viewport: 0.6, 7.6, 4.8, 5.2
    
    Axes: 0, 3, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 3, 0, 1
    
    # Normal
    if mode = 0
        Paint rectangle: "{0.5, 0.7, 0.5}", 0.1, 0.9, 0.1, 0.9
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 0.1, 0.9, 0.1, 0.9
    endif
    
    # Quantize
    if mode = 1
        Paint rectangle: "{0.5, 0.6, 0.8}", 1.1, 1.9, 0.1, 0.9
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 1.1, 1.9, 0.1, 0.9
    endif
    
    # Robot
    if mode = 2
        Paint rectangle: "{0.7, 0.5, 0.6}", 2.1, 2.9, 0.1, 0.9
    else
        Paint rectangle: "{0.8, 0.8, 0.8}", 2.1, 2.9, 0.1, 0.9
    endif
    
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 0.5, "half", "Normal"
    Text: 1.5, "centre", 0.5, "half", "Quantize"
    Text: 2.5, "centre", 0.5, "half", "Robot"
    
    Draw inner box
    Font size: 6
    Text left: "yes", "Mode"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    statsText$ = "Mode: " + modeName$
    if op_stylize > 0
        statsText$ = statsText$ + " | Stylize: " + fixed$(op_stylize, 1) + " Hz"
    endif
    if op_shift <> 0
        statsText$ = statsText$ + " | Shift: " + string$(op_shift) + " st"
    endif
    Text: 0.5, "centre", 0.5, "half", statsText$
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: manipulation, pitchTier, origPitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result