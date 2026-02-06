# ============================================================
# Praat AudioTools - Stereo_Mixer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed presets, resampling, compact form
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Mix 1-8 sounds into stereo with individual L/R gain control
#   and preset panning configurations.
#
# Usage:
#   Select 1-8 Sound objects and run this script.
#   Sounds are mixed in selection order (first selected = Sound 1).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Fixed preset calculations to work with any number of sounds
#   - Added automatic sample rate matching with resampling
#   - Compact form (fits on screen)
#   - Improved formula syntax
#   - Better duration mismatch warnings
# ============================================================

# === Input Validation (before form) ===
numSounds = numberOfSelected("Sound")
if numSounds = 0
    exitScript: "No sounds selected! Please select 1 to 8 Sound objects."
endif
if numSounds > 8
    exitScript: "Too many sounds selected! Maximum is 8."
endif

# Store sound IDs before form
for i from 1 to numSounds
    tempSoundID_'i' = selected("Sound", i)
endfor

form Stereo Mixer v0.3
    comment === PRESET PANNING ===
    optionmenu Preset: 1
        option Custom (use gains below)
        option All Center (mono sum)
        option Stereo Spread (alternate L R)
        option Wide Spread (hard L R)
        option Left Heavy
        option Right Heavy
        option Fade L to R
        option Fade R to L
        option V Shape (outside in)
    comment === CUSTOM GAINS (Sound 1-4 shown, edit script for 5-8) ===
    comment Sounds mixed in selection order
    real Gain_1_L 1.0
    real Gain_1_R 1.0
    real Gain_2_L 1.0
    real Gain_2_R 1.0
    real Gain_3_L 1.0
    real Gain_3_R 1.0
    real Gain_4_L 1.0
    real Gain_4_R 1.0
    comment === OUTPUT ===
    boolean Normalize_output 1
    real Target_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Safe Array Initialization ===
gainL# = zero#(8)
gainR# = zero#(8)

# Load form values
gainL#[1] = gain_1_L
gainR#[1] = gain_1_R
gainL#[2] = gain_2_L
gainR#[2] = gain_2_R
gainL#[3] = gain_3_L
gainR#[3] = gain_3_R
gainL#[4] = gain_4_L
gainR#[4] = gain_4_R

# Default gains for sounds 5-8 (edit here if needed)
gainL#[5] = 1.0
gainR#[5] = 1.0
gainL#[6] = 1.0
gainR#[6] = 1.0
gainL#[7] = 1.0
gainR#[7] = 1.0
gainL#[8] = 1.0
gainR#[8] = 1.0

# === Apply Presets (FIXED for any numSounds) ===
if preset = 2
    # All Center
    for i from 1 to numSounds
        gainL#[i] = 1.0
        gainR#[i] = 1.0
    endfor
    presetName$ = "Center"
elsif preset = 3
    # Stereo Spread (Alternate)
    for i from 1 to numSounds
        if (i mod 2) = 1
            gainL#[i] = 1.0
            gainR#[i] = 0.3
        else
            gainL#[i] = 0.3
            gainR#[i] = 1.0
        endif
    endfor
    presetName$ = "Spread"
elsif preset = 4
    # Wide Spread (hard L/R)
    for i from 1 to numSounds
        if (i mod 2) = 1
            gainL#[i] = 1.0
            gainR#[i] = 0.0
        else
            gainL#[i] = 0.0
            gainR#[i] = 1.0
        endif
    endfor
    presetName$ = "WideSpread"
elsif preset = 5
    # Left Heavy
    for i from 1 to numSounds
        gainL#[i] = 1.0
        gainR#[i] = 0.3
    endfor
    presetName$ = "LeftHeavy"
elsif preset = 6
    # Right Heavy
    for i from 1 to numSounds
        gainL#[i] = 0.3
        gainR#[i] = 1.0
    endfor
    presetName$ = "RightHeavy"
elsif preset = 7
    # Fade L to R (FIXED)
    for i from 1 to numSounds
        if numSounds > 1
            progress = (i - 1) / (numSounds - 1)
        else
            progress = 0
        endif
        gainL#[i] = 1.0 - progress
        gainR#[i] = progress
    endfor
    presetName$ = "FadeLR"
elsif preset = 8
    # Fade R to L (FIXED)
    for i from 1 to numSounds
        if numSounds > 1
            progress = (i - 1) / (numSounds - 1)
        else
            progress = 0
        endif
        gainL#[i] = progress
        gainR#[i] = 1.0 - progress
    endfor
    presetName$ = "FadeRL"
elsif preset = 9
    # V Shape (FIXED - outside to center)
    midpoint = (numSounds + 1) / 2
    for i from 1 to numSounds
        if i <= midpoint
            # First half: L->C
            if midpoint > 1
                progress = (i - 1) / (midpoint - 1)
            else
                progress = 0
            endif
            gainL#[i] = 1.0 - progress * 0.7
            gainR#[i] = 0.3 + progress * 0.7
        else
            # Second half: C->R
            remaining = numSounds - midpoint
            if remaining > 0
                progress = (i - midpoint) / remaining
            else
                progress = 0
            endif
            gainL#[i] = 0.3 + progress * 0.7
            gainR#[i] = 1.0 - progress * 0.7
        endif
    endfor
    presetName$ = "VShape"
else
    presetName$ = "Custom"
endif

writeInfoLine: "=== Stereo Mixer v0.3 ==="
appendInfoLine: "Mixing ", numSounds, " sounds"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# === Restore Sound IDs and Get Properties ===
maxDur = 0
minDur = 1e10
maxSR = 0

for i from 1 to numSounds
    soundID_'i' = tempSoundID_'i'
    selectObject: soundID_'i'
    soundName_'i'$ = selected$("Sound")
    
    dur = Get total duration
    sr = Get sampling frequency
    
    if dur > maxDur
        maxDur = dur
    endif
    if dur < minDur
        minDur = dur
    endif
    if sr > maxSR
        maxSR = sr
    endif
    
    appendInfoLine: "Sound ", i, ": ", soundName_'i'$, " (", fixed$(dur, 2), "s, ", sr, " Hz)"
endfor

appendInfoLine: ""
appendInfoLine: "Output duration: ", fixed$(maxDur, 3), " s"
appendInfoLine: "Sample rate: ", maxSR, " Hz"

# Warn about duration mismatches
if maxDur - minDur > 0.1
    appendInfoLine: "⚠ Duration mismatch: ", fixed$(minDur, 2), "-", fixed$(maxDur, 2), "s (shorter sounds end early)"
endif

appendInfoLine: ""

# === Create Output Buffer ===
Create Sound from formula: "mixed", 2, 0, maxDur, maxSR, "0"
resultID = selected("Sound")

# === Mixing Loop ===
appendInfoLine: "Mixing channels:"

for i from 1 to numSounds
    thisID = soundID_'i'
    thisName$ = soundName_'i'$
    
    selectObject: thisID
    nCh = Get number of channels
    thisSR = Get sampling frequency
    
    # Create temporary copy
    Copy: "temp_mix_layer"
    tempID = selected("Sound")
    
    # RESAMPLE if needed (CRITICAL FIX)
    if thisSR <> maxSR
        appendInfoLine: "  Resampling Sound ", i, " from ", thisSR, " to ", maxSR, " Hz"
        Resample: maxSR, 50
        removeObject: tempID
        tempID = selected("Sound")
    endif
    
    # Convert mono to stereo
    if nCh = 1
        selectObject: tempID
        stereoTemp = Convert to stereo
        removeObject: tempID
        tempID = stereoTemp
    endif
    
    # Get gains
    valL = gainL#[i]
    valR = gainR#[i]
    
    # Apply gains with modern syntax
    selectObject: tempID
    valLstr$ = string$(valL)
    valRstr$ = string$(valR)
    Formula (part): 0, 0, 1, 1, "self * " + valLstr$
    Formula (part): 0, 0, 2, 2, "self * " + valRstr$
    
    # Add to result (modern object reference)
    plusObj = tempID
    selectObject: resultID
    Formula: "self + object[plusObj, col]"
    
    # Cleanup
    removeObject: tempID
    
    # Calculate pan position for display
    totalGain = valL + valR
    if totalGain > 1e-6
        pan = (valR - valL) / totalGain
    else
        pan = 0
    endif
    
    if pan < -0.3
        panStr$ = "L"
    elsif pan > 0.3
        panStr$ = "R"
    else
        panStr$ = "C"
    endif
    
    appendInfoLine: "  ", i, ". ", thisName$, " -> L:", fixed$(valL, 2), " R:", fixed$(valR, 2), " [", panStr$, "]"
endfor

# === Post Processing ===
selectObject: resultID

if normalize_output
    Scale peak: target_peak
    appendInfoLine: ""
    appendInfoLine: "Normalized to peak: ", target_peak
endif

resultName$ = "Mixed_" + presetName$ + "_" + string$(numSounds) + "ch"
Rename: resultName$

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Mixer: " + resultName$
    
    # === Stereo Field (Left Panel) ===
    Select outer viewport: 0, 4, 0.8, 4.5
    Select inner viewport: 0.5, 3.8, 1.0, 4.3
    
    Axes: -1.3, 1.3, 0, numSounds + 1
    
    # Background
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.3, 1.3, 0, numSounds + 1
    
    # Center guide
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, 0, numSounds + 1
    Solid line
    
    # L/R boundary lines
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1, 0, -1, numSounds + 1
    Draw line: 1, 0, 1, numSounds + 1
    
    # Draw sound positions
    for i from 1 to numSounds
        yPos = numSounds - i + 1
        l = gainL#[i]
        r = gainR#[i]
        
        # Calculate pan position (-1 to +1)
        totalGain = l + r
        if totalGain > 1e-6
            pan = (r - l) / totalGain
        else
            pan = 0
        endif
        
        # Size based on total gain
        avgGain = totalGain / 2
        circleSize = 2 + avgGain * 2
        if circleSize < 1
            circleSize = 1
        endif
        if circleSize > 5
            circleSize = 5
        endif
        
        # Color: blue for left, orange for right, gray for center
        if pan < -0.2
            col$ = "{0.2, 0.4, 0.8}"
        elsif pan > 0.2
            col$ = "{0.8, 0.5, 0.2}"
        else
            col$ = "{0.5, 0.5, 0.5}"
        endif
        
        Paint circle (mm): col$, pan, yPos, circleSize
        
        # Label
        Colour: "Black"
        Font size: 8
        Text: -1.25, "left", yPos, "half", string$(i)
    endfor
    
    # Axis labels
    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    Text: -1, "centre", 0.3, "half", "L"
    Text: 0, "centre", 0.3, "half", "C"
    Text: 1, "centre", 0.3, "half", "R"
    
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text top: "no", "Stereo Field"
    
    # === Gain Bars (Middle Panel) ===
    Select outer viewport: 4, 7, 0.8, 4.5
    Select inner viewport: 4.3, 6.8, 1.0, 4.3
    
    Axes: 0, 2.2, 0, numSounds + 1
    
    # Background
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 2.2, 0, numSounds + 1
    
    barHeight = 0.35
    
    for i from 1 to numSounds
        yPos = numSounds - i + 1
        l = gainL#[i]
        r = gainR#[i]
        
        # Left gain bar (blue)
        Colour: "{0.3, 0.5, 0.8}"
        Paint rectangle: "{0.3, 0.5, 0.8}", 0, l, yPos - barHeight, yPos
        
        # Right gain bar (orange)
        Colour: "{0.8, 0.6, 0.3}"
        Paint rectangle: "{0.8, 0.6, 0.3}", 0, r, yPos, yPos + barHeight
        
        # Labels
        Colour: "Black"
        Font size: 7
        Text: l + 0.05, "left", yPos - barHeight/2, "half", fixed$(l, 1)
        Text: r + 0.05, "left", yPos + barHeight/2, "half", fixed$(r, 1)
    endfor
    
    # Unity line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 1, 0, 1, numSounds + 1
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text top: "no", "L/R Gains"
    
    # Legend
    Font size: 7
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.3, "centre", 0.4, "half", "L"
    Colour: "{0.8, 0.6, 0.3}"
    Text: 0.7, "centre", 0.4, "half", "R"
    
    # === Output Waveform (Right Panel) ===
    Select outer viewport: 7, 10, 0.8, 4.5
    Select inner viewport: 7.3, 9.8, 1.0, 4.3
    
    selectObject: resultID
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text top: "no", "Mixed Output"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Output ===
selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Result: ", resultName$

if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID