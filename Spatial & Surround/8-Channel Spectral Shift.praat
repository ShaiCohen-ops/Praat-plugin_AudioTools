# ============================================================
# Praat AudioTools - 8-Channel_Spectral_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creates 8-voice frequency shift canons via FFT bin shifting.
#   Shifts spectrum up or down by specified number of bins.
#
# Changelog v0.3:
#   - Refactored to use loops
#   - Fixed cleanup
#   - Added negative shifts (down)
#   - Added visualization
#   - Modern syntax
# ============================================================

form 8-Channel Spectral Shift
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Gentle Up (50-200 bins)"
        option: "Moderate Up (200-500 bins)"
        option: "Extreme Up (500-1500 bins)"
        option: "Symmetrical (up/down mirror)"
        option: "All Down (-100 to -400 bins)"
        option: "Spread (down to up)"
        option: "Cluster Up (small spread)"
        option: "Octave-like (doubling pattern)"
    
    comment === Bin shift amounts (positive=up, negative=down) ===
    integer Shift_1 100
    integer Shift_2 200
    integer Shift_3 300
    integer Shift_4 400
    integer Shift_5 -100
    integer Shift_6 -200
    integer Shift_7 -300
    integer Shift_8 -400
    
    comment === Output ===
    real Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Up
    shift_1 = 50
    shift_2 = 75
    shift_3 = 100
    shift_4 = 125
    shift_5 = 150
    shift_6 = 175
    shift_7 = 200
    shift_8 = 225
    presetName$ = "GentleUp"
elsif preset = 3
    # Moderate Up
    shift_1 = 200
    shift_2 = 250
    shift_3 = 300
    shift_4 = 350
    shift_5 = 400
    shift_6 = 450
    shift_7 = 500
    shift_8 = 550
    presetName$ = "ModerateUp"
elsif preset = 4
    # Extreme Up
    shift_1 = 500
    shift_2 = 650
    shift_3 = 800
    shift_4 = 950
    shift_5 = 1100
    shift_6 = 1250
    shift_7 = 1400
    shift_8 = 1550
    presetName$ = "ExtremeUp"
elsif preset = 5
    # Symmetrical
    shift_1 = 400
    shift_2 = 300
    shift_3 = 200
    shift_4 = 100
    shift_5 = -100
    shift_6 = -200
    shift_7 = -300
    shift_8 = -400
    presetName$ = "Symmetrical"
elsif preset = 6
    # All Down
    shift_1 = -100
    shift_2 = -150
    shift_3 = -200
    shift_4 = -250
    shift_5 = -300
    shift_6 = -350
    shift_7 = -400
    shift_8 = -450
    presetName$ = "AllDown"
elsif preset = 7
    # Spread (down to up)
    shift_1 = -400
    shift_2 = -250
    shift_3 = -100
    shift_4 = 0
    shift_5 = 0
    shift_6 = 100
    shift_7 = 250
    shift_8 = 400
    presetName$ = "Spread"
elsif preset = 8
    # Cluster Up
    shift_1 = 100
    shift_2 = 110
    shift_3 = 120
    shift_4 = 130
    shift_5 = 140
    shift_6 = 150
    shift_7 = 160
    shift_8 = 170
    presetName$ = "ClusterUp"
elsif preset = 9
    # Octave-like
    shift_1 = 50
    shift_2 = 100
    shift_3 = 200
    shift_4 = 400
    shift_5 = -50
    shift_6 = -100
    shift_7 = -200
    shift_8 = -400
    presetName$ = "OctaveLike"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency

# === Store shifts in array ===
shiftAmt[1] = shift_1
shiftAmt[2] = shift_2
shiftAmt[3] = shift_3
shiftAmt[4] = shift_4
shiftAmt[5] = shift_5
shiftAmt[6] = shift_6
shiftAmt[7] = shift_7
shiftAmt[8] = shift_8

# === Create mono base ===
selectObject: originalID
Copy: "base_work"
baseWorkID = selected("Sound")
Convert to mono
monoID = selected("Sound")

# === Info ===
writeInfoLine: "=== 8-Channel Spectral Shift ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# === Process each channel ===
for ch from 1 to 8
    selectObject: monoID
    Copy: "ch_temp"
    tempID = selected("Sound")
    
    # Convert to spectrum
    To Spectrum: "yes"
    specID = selected("Spectrum")
    
    # Get shift amount
    s = shiftAmt[ch]
    
    # Apply shift formula
    if s >= 0
        # Shift UP: take from higher bins
        Formula: "if col + 's' <= ncol then self[col + 's'] else 0 fi"
        dir$ = "+"
    else
        # Shift DOWN: take from lower bins
        sAbs = abs(s)
        Formula: "if col - 'sAbs' >= 1 then self[col - 'sAbs'] else 0 fi"
        dir$ = ""
    endif
    
    # Convert back to sound
    To Sound
    shifted[ch] = selected("Sound")
    Scale peak: scale_peak
    
    # Cleanup temp
    removeObject: tempID, specID
    
    appendInfoLine: "  Ch", ch, ": ", dir$, s, " bins"
endfor

# === Combine all 8 channels ===
selectObject: shifted[1], shifted[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: shifted[3], shifted[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: shifted[5], shifted[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: shifted[7], shifted[8]
Combine to stereo
pair78 = selected("Sound")

selectObject: pair12, pair34
Combine to stereo
quad1234 = selected("Sound")

selectObject: pair56, pair78
Combine to stereo
quad5678 = selected("Sound")

selectObject: quad1234, quad5678
Combine to stereo
result = selected("Sound")
Scale peak: scale_peak
Rename: originalName$ + "_8chSpectral_" + presetName$

# === Cleanup ===
removeObject: baseWorkID, monoID
for ch from 1 to 8
    removeObject: shifted[ch]
endfor
removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "8-Channel Spectral Shift: " + presetName$ + " | " + originalName$
    
    # Find min/max for scaling
    minShift = shiftAmt[1]
    maxShift = shiftAmt[1]
    for ch from 2 to 8
        if shiftAmt[ch] < minShift
            minShift = shiftAmt[ch]
        endif
        if shiftAmt[ch] > maxShift
            maxShift = shiftAmt[ch]
        endif
    endfor
    
    # Add margin
    range = maxShift - minShift
    if range < 100
        range = 100
    endif
    plotMin = minShift - range * 0.15
    plotMax = maxShift + range * 0.15
    
    # Bar chart of shifts
    Select outer viewport: 0.5, 9.5, 0.8, 4.0
    Select inner viewport: 1.0, 9.0, 1.2, 3.7
    
    Axes: 0, 9, plotMin, plotMax
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 9, plotMin, plotMax
    
    # Zero line
    if plotMin < 0 and plotMax > 0
        Colour: "{0.5, 0.5, 0.5}"
        Dotted line
        Draw line: 0, 0, 9, 0
        Solid line
    endif
    
    # Draw bars for each channel
    for ch from 1 to 8
        s = shiftAmt[ch]
        xL = ch - 0.4
        xR = ch + 0.4
        
        if s >= 0
            # Positive = blue (shift up)
            Paint rectangle: "{0.3, 0.5, 0.8}", xL, xR, 0, s
            Colour: "Black"
            Draw rectangle: xL, xR, 0, s
        else
            # Negative = red (shift down)
            Paint rectangle: "{0.8, 0.4, 0.3}", xL, xR, s, 0
            Colour: "Black"
            Draw rectangle: xL, xR, s, 0
        endif
        
        # Label
        Font size: 7
        Colour: "Black"
        lblY = plotMin + range * 0.05
        Text: ch, "centre", lblY, "half", "Ch" + string$(ch)
    endfor
    
    # Axes
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 100, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "Bin shift"
    
    # Legend
    Font size: 7
    legTop = plotMax - range * 0.05
    legMid = plotMax - range * 0.125
    legBot = plotMax - range * 0.175
    Paint rectangle: "{0.3, 0.5, 0.8}", 7.5, 7.8, legMid, legTop
    Text: 7.9, "left", legTop - range * 0.0375, "half", "Up"
    Paint rectangle: "{0.8, 0.4, 0.3}", 7.5, 7.8, legBot, legMid
    Text: 7.9, "left", legMid - range * 0.025, "half", "Down"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 4.2, 6.0
    Select inner viewport: 1.0, 9.0, 4.4, 5.8
    selectObject: result
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output (8ch)"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel spectral shift"

if play_result
    selectObject: result
    Play
endif

selectObject: result