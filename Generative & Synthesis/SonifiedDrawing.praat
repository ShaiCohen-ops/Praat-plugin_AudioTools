# ============================================================
# Praat AudioTools - Sonified_Drawing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Real-time drawing sonification instrument. Draws geometric shapes
#   while generating sound based on position:
#   - Distance from center → Pitch (with optional scale quantization)
#   - X position → Stereo pan
#   - Y position → Amplitude
#
#   Supports morphing between two shapes and various musical scales.
#   Inspired by UPIC and graphical synthesis systems.
#
# Usage:
#   Run this script, select shapes and scale, watch it draw and listen.
#
# Changelog v0.2:
#   - Fixed output deletion bug (now accumulates final sound)
#   - Added proper viewport setup
#   - Modern syntax
#   - Added visualization of trajectory
# ============================================================

form Sonified Drawing
    comment === Shape Selection ===
    optionmenu Shape_1 2
        option Spiral
        option Circle
        option Square
        option Triangle
        option Lissajous
        option Rose
        option Figure8
    optionmenu Shape_2 5
        option Spiral
        option Circle
        option Square
        option Triangle
        option Lissajous
        option Rose
        option Figure8
    
    comment === Musical Scale ===
    optionmenu Scale 1
        option Original (Unquantized)
        option Pentatonic Minor
        option Major
        option Natural Minor
        option Dorian
        option Pentatonic Major
    
    comment === Tone Type ===
    optionmenu Tone 2
        option One Sine (Pure)
        option Two Sines (Richer)
    
    comment === Morphing ===
    real Morph_speed 0.01
    
    comment === Drawing Parameters ===
    integer Steps 200
    positive Note_duration_s 0.04
    real Angular_speed 0.25
    real Spiral_growth 0.22
    
    comment === Shape Parameters ===
    real Lissajous_a 3
    real Lissajous_b 2
    real Rose_k 5
    
    comment === Sound Parameters ===
    positive Tonic_Hz 110
    integer Sample_rate_Hz 22050
    
    comment === Playback ===
    integer Play_every_n_steps 1
    boolean Create_final_sound 1
endform

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
centerX = 50
centerY = 50

# === Info ===
writeInfoLine: "=== Sonified Drawing ==="
appendInfoLine: "Shape 1: ", shape_1
appendInfoLine: "Shape 2: ", shape_2
appendInfoLine: "Scale: ", scale
appendInfoLine: "Steps: ", steps
appendInfoLine: ""

# === Setup Drawing ===
Erase all
Select outer viewport: 0, 6, 0, 6
Select inner viewport: 0.5, 5.5, 0.5, 5.5
Axes: 0, 100, 0, 100

# Draw center point
Colour: "{0.8, 0.8, 0.8}"
Paint circle (mm): "{0.9, 0.9, 0.9}", centerX, centerY, 3

# Initialize
prevX = centerX
prevY = centerY
morphProgress = 0

# Store trajectory for final output
for st to steps
    trajX[st] = centerX
    trajY[st] = centerY
    trajFreq[st] = tonic_Hz
    trajAmp[st] = 0.5
    trajPan[st] = 0.5
endfor

# === Define Scale Intervals (semitones) ===
# Pentatonic Minor: 0, 3, 5, 7, 10
pentMinor[1] = 0
pentMinor[2] = 3
pentMinor[3] = 5
pentMinor[4] = 7
pentMinor[5] = 10
nPentMinor = 5

# Major: 0, 2, 4, 5, 7, 9, 11
major[1] = 0
major[2] = 2
major[3] = 4
major[4] = 5
major[5] = 7
major[6] = 9
major[7] = 11
nMajor = 7

# Natural Minor: 0, 2, 3, 5, 7, 8, 10
natMinor[1] = 0
natMinor[2] = 2
natMinor[3] = 3
natMinor[4] = 5
natMinor[5] = 7
natMinor[6] = 8
natMinor[7] = 10
nNatMinor = 7

# Dorian: 0, 2, 3, 5, 7, 9, 10
dorian[1] = 0
dorian[2] = 2
dorian[3] = 3
dorian[4] = 5
dorian[5] = 7
dorian[6] = 9
dorian[7] = 10
nDorian = 7

# Pentatonic Major: 0, 2, 4, 7, 9
pentMajor[1] = 0
pentMajor[2] = 2
pentMajor[3] = 4
pentMajor[4] = 7
pentMajor[5] = 9
nPentMajor = 5

# === Main Drawing Loop ===
appendInfoLine: "Drawing and sonifying..."

for t to steps
    # Update morph progress
    morphProgress = morphProgress + morph_speed
    if morphProgress > 1
        morphProgress = 0
    endif
    
    angle = t * angular_speed
    
    # === Calculate Shape 1 Position ===
    @getShapePosition: shape_1, t, angle
    px1 = getShapePosition.x
    py1 = getShapePosition.y
    
    # === Calculate Shape 2 Position ===
    @getShapePosition: shape_2, t, angle
    px2 = getShapePosition.x
    py2 = getShapePosition.y
    
    # === Morph Between Shapes ===
    px = px1 * (1 - morphProgress) + px2 * morphProgress
    py = py1 * (1 - morphProgress) + py2 * morphProgress
    
    # === Draw Line ===
    # Color based on morph progress
    r = 0.2 + 0.6 * morphProgress
    g = 0.4 + 0.3 * (1 - morphProgress)
    b = 0.8 - 0.4 * morphProgress
    Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
    Line width: 1.5
    Draw line: prevX, prevY, px, py
    
    # === Calculate Distance from Center ===
    dist = sqrt((px - centerX)^2 + (py - centerY)^2)
    
    # === Calculate Frequency Based on Scale ===
    if scale = 1
        # Unquantized
        baseFreq = 140 + 3 * dist
    else
        # Quantized to scale
        if scale = 2
            nScale = nPentMinor
            idx = (floor(dist) mod nScale) + 1
            semi = pentMinor[idx]
        elsif scale = 3
            nScale = nMajor
            idx = (floor(dist) mod nScale) + 1
            semi = major[idx]
        elsif scale = 4
            nScale = nNatMinor
            idx = (floor(dist) mod nScale) + 1
            semi = natMinor[idx]
        elsif scale = 5
            nScale = nDorian
            idx = (floor(dist) mod nScale) + 1
            semi = dorian[idx]
        else
            nScale = nPentMajor
            idx = (floor(dist) mod nScale) + 1
            semi = pentMajor[idx]
        endif
        
        octave = floor(dist / 10) * 12
        semiTotal = semi + octave
        baseFreq = tonic_Hz * 2^(semiTotal / 12)
    endif
    
    # === Calculate Pan and Amplitude ===
    pan = (px - centerX) / 50
    pan = max(-1, min(1, pan))
    
    amp = 0.4 + (py / 100) * 0.5
    amp = max(0.1, min(1, amp))
    
    # Constant power panning
    panAngle = (pan + 1) * (pi / 4)
    leftGain = cos(panAngle)
    rightGain = sin(panAngle)
    
    # Store trajectory
    trajX[t] = px
    trajY[t] = py
    trajFreq[t] = baseFreq
    trajAmp[t] = amp
    trajPan[t] = (pan + 1) / 2
    
    # === Create and Play Sound ===
    if ((t - 1) mod play_every_n_steps) = 0
        dur$ = fixed$(note_duration_s, 4)
        freq$ = fixed$(baseFreq, 2)
        lGain$ = fixed$(leftGain * amp, 4)
        rGain$ = fixed$(rightGain * amp, 4)
        
        # Envelope
        envFormula$ = "(sin(pi * x / " + dur$ + "))^2"
        
        # Tone
        if tone = 1
            toneFormula$ = "sin(twoPi * " + freq$ + " * x)"
        else
            toneFormula$ = "sin(twoPi * " + freq$ + " * x) + 0.3 * sin(twoPi * " + freq$ + " * 2 * x)"
        endif
        
        # Create stereo grain
        leftSound = Create Sound from formula: "L_" + uid$, 1, 0, note_duration_s, sample_rate_Hz, lGain$ + " * " + envFormula$ + " * " + toneFormula$
        
        rightSound = Create Sound from formula: "R_" + uid$, 1, 0, note_duration_s, sample_rate_Hz, rGain$ + " * " + envFormula$ + " * " + toneFormula$
        
        selectObject: leftSound
        plusObject: rightSound
        grainSound = Combine to stereo
        
        # Play
        selectObject: grainSound
        Play
        
        # Cleanup grain
        removeObject: leftSound, rightSound, grainSound
    endif
    
    # Update previous position
    prevX = px
    prevY = py
    
    if t mod 50 = 0
        appendInfoLine: "  Step ", t, "/", steps
    endif
endfor

Line width: 1
Colour: "Black"

# === Create Final Combined Sound ===
if create_final_sound
    appendInfoLine: ""
    appendInfoLine: "Creating final sound..."
    
    totalDuration = steps * note_duration_s
    
    finalLeft = Create Sound from formula: "finalL_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
    finalRight = Create Sound from formula: "finalR_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
    
    # Chunked synthesis
    grainsPerChunk = 20
    nChunks = ceiling(steps / grainsPerChunk)
    
    for chunk to nChunks
        startStep = (chunk - 1) * grainsPerChunk + 1
        endStep = min(chunk * grainsPerChunk, steps)
        
        leftFormula$ = ""
        rightFormula$ = ""
        
        for st from startStep to endStep
            noteStart = (st - 1) * note_duration_s
            freq = trajFreq[st]
            amp = trajAmp[st]
            pan = trajPan[st]
            
            leftGain = sqrt(1 - pan) * amp
            rightGain = sqrt(pan) * amp
            
            t$ = fixed$(noteStart, 6)
            d$ = fixed$(note_duration_s, 6)
            f$ = fixed$(freq, 2)
            lG$ = fixed$(leftGain, 4)
            rG$ = fixed$(rightGain, 4)
            
            # Envelope + tone
            if tone = 1
                grainL$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + lG$ + " * (sin(pi * (x - " + t$ + ") / " + d$ + "))^2 * sin(twoPi * " + f$ + " * x) else 0 fi"
                grainR$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + rG$ + " * (sin(pi * (x - " + t$ + ") / " + d$ + "))^2 * sin(twoPi * " + f$ + " * x) else 0 fi"
            else
                grainL$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + lG$ + " * (sin(pi * (x - " + t$ + ") / " + d$ + "))^2 * (sin(twoPi * " + f$ + " * x) + 0.3 * sin(twoPi * " + f$ + " * 2 * x)) else 0 fi"
                grainR$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + rG$ + " * (sin(pi * (x - " + t$ + ") / " + d$ + "))^2 * (sin(twoPi * " + f$ + " * x) + 0.3 * sin(twoPi * " + f$ + " * 2 * x)) else 0 fi"
            endif
            
            if leftFormula$ = ""
                leftFormula$ = grainL$
                rightFormula$ = grainR$
            else
                leftFormula$ = leftFormula$ + " + " + grainL$
                rightFormula$ = rightFormula$ + " + " + grainR$
            endif
        endfor
        
        selectObject: finalLeft
        Formula: "self + (" + leftFormula$ + ")"
        
        selectObject: finalRight
        Formula: "self + (" + rightFormula$ + ")"
    endfor
    
    # Combine to stereo
    selectObject: finalLeft
    plusObject: finalRight
    outputSound = Combine to stereo
    Rename: "sonified_drawing_" + uid$
    
    removeObject: finalLeft, finalRight
    
    # Fade
    selectObject: outputSound
    Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
    Formula: "if x > totalDuration - 0.05 then self * ((totalDuration - x) / 0.05) else self fi"
    
    # Normalize
    Scale peak: 0.9
    
    selectObject: outputSound
    appendInfoLine: ""
    appendInfoLine: "=== Done ==="
    appendInfoLine: "Created: ", selected$("Sound")
else
    appendInfoLine: ""
    appendInfoLine: "=== Done (no final sound created) ==="
endif

# ==============================================================================
# Procedure: getShapePosition
# ==============================================================================
procedure getShapePosition: .shape, .t, .angle
    
    if .shape = 1
        # Spiral
        .radius = .t * spiral_growth
        .x = centerX + .radius * cos(.angle)
        .y = centerY + .radius * sin(.angle)
        
    elsif .shape = 2
        # Circle
        .r0 = 30
        .x = centerX + .r0 * cos(.angle)
        .y = centerY + .r0 * sin(.angle)
        
    elsif .shape = 3
        # Square
        .s = 60
        .half = .s / 2
        .p = .t / steps
        .p4 = .p * 4
        if .p4 < 1
            .x = centerX - .half + .p4 * .s
            .y = centerY - .half
        elsif .p4 < 2
            .x = centerX + .half
            .y = centerY - .half + (.p4 - 1) * .s
        elsif .p4 < 3
            .x = centerX + .half - (.p4 - 2) * .s
            .y = centerY + .half
        else
            .x = centerX - .half
            .y = centerY + .half - (.p4 - 3) * .s
        endif
        
    elsif .shape = 4
        # Triangle
        .s = 60
        .h = .s * sqrt(3) / 2
        .ax = centerX
        .ay = centerY - .h / 2
        .bx = centerX + .s / 2
        .by = centerY + .h / 2
        .cx = centerX - .s / 2
        .cy = centerY + .h / 2
        .p = .t / steps
        .p3 = .p * 3
        if .p3 < 1
            .x = .ax + (.bx - .ax) * .p3
            .y = .ay + (.by - .ay) * .p3
        elsif .p3 < 2
            .u = .p3 - 1
            .x = .bx + (.cx - .bx) * .u
            .y = .by + (.cy - .by) * .u
        else
            .u = .p3 - 2
            .x = .cx + (.ax - .cx) * .u
            .y = .cy + (.ay - .cy) * .u
        endif
        
    elsif .shape = 5
        # Lissajous
        .aamp = 30
        .bamp = 30
        .x = centerX + .aamp * sin(lissajous_a * .angle)
        .y = centerY + .bamp * sin(lissajous_b * .angle + pi/2)
        
    elsif .shape = 6
        # Rose
        .rmax = 35
        .r = .rmax * cos(rose_k * .angle)
        .x = centerX + .r * cos(.angle)
        .y = centerY + .r * sin(.angle)
        
    else
        # Figure 8 (Lemniscate)
        .a8 = 35
        .denom = 1 + (sin(.angle))^2
        .x = centerX + .a8 * cos(.angle) / .denom
        .y = centerY + .a8 * sin(.angle) * cos(.angle) / .denom
    endif
endproc
