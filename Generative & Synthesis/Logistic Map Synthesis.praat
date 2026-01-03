# ============================================================
# Praat AudioTools - Logistic_Map_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Enhanced
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Logistic map synthesis with cobweb plot visualization.
#   The logistic map: x[n+1] = r × x[n] × (1 - x[n])
#
#   Behavior by r parameter:
#   - r < 3.0: Converges to fixed point
#   - r ≈ 3.45: Period-2 oscillation
#   - r ≈ 3.54: Period-4 oscillation  
#   - r ≈ 3.57: Onset of chaos (Feigenbaum point)
#   - r = 4.0: Full chaos
#
# Usage:
#   Run this script (no input sound required).
#
# Changelog v0.2:
#   - Added fade in/out
#   - Added spectrogram panel
#   - Fixed preset_name$ for Custom
# ============================================================

form Logistic Map Synthesis
    comment === Preset ===
    optionmenu Preset 6
        option Custom (use settings below)
        option Gentle Chaos (r=3.5)
        option Wild Oscillations (r=3.9)
        option Periodic Orbit (r=3.2)
        option Edge of Chaos (r=3.57)
        option Bifurcation Cascade (r=3.55)
        option Strange Attractor (r=3.8)
    
    comment === Basic Settings ===
    positive Duration_s 10.0
    positive Base_frequency_Hz 180
    
    comment === Logistic Map Parameters ===
    real R_parameter 3.7 (= 2.5-4.0)
    real Initial_x 0.5 (= 0.01-0.99)
    
    comment === Visualization ===
    positive Cobweb_iterations 50
    optionmenu Plot_type 3
        option Cobweb Plot
        option Return Map (attractor dots)
        option Both
    boolean Draw_visualization 1
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating Pan
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    r_parameter = 3.5
    base_frequency_Hz = 150
    initial_x = 0.3
    preset_name$ = "GentleChaos"
elsif preset = 3
    r_parameter = 3.9
    base_frequency_Hz = 200
    initial_x = 0.1
    preset_name$ = "WildOscillations"
elsif preset = 4
    r_parameter = 3.2
    base_frequency_Hz = 120
    initial_x = 0.7
    preset_name$ = "PeriodicOrbit"
elsif preset = 5
    r_parameter = 3.56995
    base_frequency_Hz = 170
    initial_x = 0.5
    preset_name$ = "EdgeOfChaos"
elsif preset = 6
    r_parameter = 3.55
    base_frequency_Hz = 140
    initial_x = 0.4
    preset_name$ = "BifurcationCascade"
elsif preset = 7
    r_parameter = 3.8
    base_frequency_Hz = 190
    initial_x = 0.2
    preset_name$ = "StrangeAttractor"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
controlRate = 200
sampleRate = 44100

# === Info ===
writeInfoLine: "=== Logistic Map Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "R parameter: ", r_parameter
appendInfoLine: "Initial x: ", initial_x
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: ""

# === 1. Compute Logistic Map at Control Rate ===
appendInfoLine: "Computing logistic map..."

ctrlSound = Create Sound from formula: "ctrl_" + uid$, 1, 0, duration_s, controlRate, "0"
totalCtrlSamples = Get number of samples

logisticX = initial_x
for i to totalCtrlSamples
    logisticX = r_parameter * logisticX * (1 - logisticX)
    Set value at sample number: 1, i, logisticX
endfor

# === 2. Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0.2, 0.8
    Select inner viewport: 0, 8, 0.2, 0.8
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Logistic Map Synthesis — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "x[n+1] = r × x[n] × (1 - x[n])  |  r = " + fixed$(r_parameter, 4)
    
    # === Cobweb/Return Map Panel ===
    Select outer viewport: 0, 4, 1.0, 4.5
    Select inner viewport: 0.5, 3.8, 1.2, 4.3
    Axes: 0, 1, 0, 1
    
    # Background
    Colour: "{0.98, 0.98, 0.98}"
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, 0, 1
    
    # Draw parabola (the logistic map curve)
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    for px from 0 to 100
        pxVal = px / 100
        pxVal2 = (px + 1) / 100
        pyVal = r_parameter * pxVal * (1 - pxVal)
        pyVal2 = r_parameter * pxVal2 * (1 - pxVal2)
        if pyVal <= 1 and pyVal2 <= 1 and pyVal >= 0 and pyVal2 >= 0
            Draw line: pxVal, pyVal, pxVal2, pyVal2
        endif
    endfor
    
    # Draw diagonal (y = x)
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1
    Draw line: 0, 0, 1, 1
    
    # Draw cobweb
    if plot_type = 1 or plot_type = 3
        selectObject: ctrlSound
        currVal = Get value at sample number: 1, 1
        
        Colour: "{0.9, 0.2, 0.2}"
        Line width: 1
        
        iters = min(cobweb_iterations, totalCtrlSamples - 1)
        
        for i to iters
            nextVal = Get value at sample number: 1, i + 1
            if currVal >= 0 and currVal <= 1 and nextVal >= 0 and nextVal <= 1
                # Vertical line (to parabola)
                Draw line: currVal, currVal, currVal, nextVal
                # Horizontal line (to diagonal)
                Draw line: currVal, nextVal, nextVal, nextVal
            endif
            currVal = nextVal
        endfor
        
        # Starting point
        Colour: "{0.2, 0.8, 0.2}"
        Paint circle (mm): "{0.2, 0.8, 0.2}", initial_x, 0, 2
    endif
    
    # Draw attractor dots (return map)
    if plot_type = 2 or plot_type = 3
        selectObject: ctrlSound
        
        Colour: "{1, 0.5, 0}"
        
        # Skip transient
        startIdx = round(totalCtrlSamples * 0.2)
        
        for i from startIdx to totalCtrlSamples - 1
            if (i mod 3) = 0
                valX = Get value at sample number: 1, i
                valY = Get value at sample number: 1, i + 1
                if valX >= 0 and valX <= 1 and valY >= 0 and valY <= 1
                    Paint circle (mm): "{1, 0.5, 0}", valX, valY, 0.4
                endif
            endif
        endfor
    endif
    
    # Box and labels
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks bottom every: 1, 0.2, "yes", "yes", "no"
    Marks left every: 1, 0.2, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "x[n]"
    Text left: "yes", "x[n+1]"
endif

# === 3. Audio Synthesis ===
appendInfoLine: "Synthesizing audio..."

selectObject: ctrlSound
outputSound = Resample: sampleRate, 50
Rename: "logistic_" + uid$

# Apply FM/AM using logistic values
Formula: "0.4 * self * sin(twoPi * (base_frequency_Hz * (0.5 + self)) * x)"

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === 4. Spatial Processing ===
if spatial_mode = 2
    # Stereo Wide
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 2500, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 200, 5000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "logistic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating Pan
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * 0.2 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * 0.2 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "logistic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "logistic_" + preset_name$
endif

# === Cleanup control signal ===
removeObject: ctrlSound

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Add spectrogram to visualization ===
if draw_visualization
    Select outer viewport: 4, 8, 1.0, 4.5
    Select inner viewport: 4.3, 7.8, 1.2, 4.3
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        monoSpec = selected("Sound")
    endif
    
    selectObject: monoSpec
    To Spectrogram: 0.03, 2000, 0.005, 20, "Gaussian"
    spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: monoSpec, spec
    
    Select inner viewport: 4.3, 7.8, 1.2, 4.3
    Axes: 0, duration_s, 0, 2000
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # Footer
    Select outer viewport: 0, 8, 4.6, 5.0
    Select inner viewport: 0, 8, 4.6, 5.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Left: Cobweb/Return map | Right: Audio spectrogram | Base freq: " + fixed$(base_frequency_Hz, 0) + " Hz"
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")