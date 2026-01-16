# ============================================================
# Praat AudioTools - DBAP_with_Movement_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   DBAP (Distance-Based Amplitude Panning) with Movement Control
#   Spatializes sound using distance-based gain calculation.
#   Supports 2-8 speaker configurations and 10 movement patterns.
#
# Changelog v0.2:
#   - Fixed form placement (must be first)
#   - Added visualization
#   - Added play toggle
#   - Fixed header
# ============================================================

form DBAP Movement Control
    comment === MOVEMENT TRAJECTORY ===
    optionmenu Movement_type: 2
        option: "1. Linear"
        option: "2. Circular"
        option: "3. Figure-8"
        option: "4. Spiral In"
        option: "5. Spiral Out"
        option: "6. Pendulum"
        option: "7. Zigzag"
        option: "8. Random Walk"
        option: "9. Ellipse"
        option: "10. Square"
    
    comment === Linear movement endpoints ===
    real Start_x -1.0
    real Start_y 0.0
    real End_x 1.0
    real End_y 0.0
    
    comment === Circular/pattern settings ===
    real Radius 0.8
    real Speed 1.0
    
    comment === SPEAKER CONFIGURATION ===
    optionmenu Speaker_preset: 8
        option: "Stereo (2)"
        option: "Triangle (3)"
        option: "Quad (4)"
        option: "Pentagon (5)"
        option: "Hexagon (6)"
        option: "Surround 5.1 (6)"
        option: "Surround 7.1 (8)"
        option: "Octagon (8)"
    
    comment === DBAP settings ===
    positive Chunk_duration 0.02
    positive Rolloff 1.0
    boolean Normalize_gains 1
    
    comment === OUTPUT ===
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

# === Movement names ===
movementNames$[1] = "Linear"
movementNames$[2] = "Circular"
movementNames$[3] = "Figure8"
movementNames$[4] = "SpiralIn"
movementNames$[5] = "SpiralOut"
movementNames$[6] = "Pendulum"
movementNames$[7] = "Zigzag"
movementNames$[8] = "RandomWalk"
movementNames$[9] = "Ellipse"
movementNames$[10] = "Square"
movementName$ = movementNames$[movement_type]

# === Setup speaker configuration ===
if speaker_preset = 1
    numSpeakers = 2
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkX[2] = 1.0
    spkY[2] = 0.0
    configName$ = "Stereo"
elsif speaker_preset = 2
    numSpeakers = 3
    spkX[1] = -0.866
    spkY[1] = -0.5
    spkX[2] = 0.866
    spkY[2] = -0.5
    spkX[3] = 0.0
    spkY[3] = 1.0
    configName$ = "Triangle"
elsif speaker_preset = 3
    numSpeakers = 4
    for i from 1 to 4
        angle = (i - 1) * 2 * pi / 4
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    configName$ = "Quad"
elsif speaker_preset = 4
    numSpeakers = 5
    for i from 1 to 5
        angle = (i - 1) * 2 * pi / 5 - pi / 2
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    configName$ = "Pentagon"
elsif speaker_preset = 5
    numSpeakers = 6
    for i from 1 to 6
        angle = (i - 1) * 2 * pi / 6
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    configName$ = "Hexagon"
elsif speaker_preset = 6
    numSpeakers = 6
    spkX[1] = -0.7
    spkY[1] = 0.7
    spkX[2] = 0.7
    spkY[2] = 0.7
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkX[4] = -0.7
    spkY[4] = -0.5
    spkX[5] = 0.7
    spkY[5] = -0.5
    spkX[6] = 0.0
    spkY[6] = -0.3
    configName$ = "5.1"
elsif speaker_preset = 7
    numSpeakers = 8
    spkX[1] = -0.7
    spkY[1] = 0.7
    spkX[2] = 0.7
    spkY[2] = 0.7
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkX[4] = -1.0
    spkY[4] = 0.0
    spkX[5] = 1.0
    spkY[5] = 0.0
    spkX[6] = -0.7
    spkY[6] = -0.7
    spkX[7] = 0.7
    spkY[7] = -0.7
    spkX[8] = 0.0
    spkY[8] = -0.3
    configName$ = "7.1"
else
    numSpeakers = 8
    for i from 1 to 8
        angle = (i - 1) * 2 * pi / 8
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    configName$ = "Octagon"
endif

# === Info ===
writeInfoLine: "=== DBAP with Movement Control ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 2), "s"
appendInfoLine: "Movement: ", movementName$
appendInfoLine: "Speakers: ", numSpeakers, " (", configName$, ")"
appendInfoLine: "Rolloff: ", rolloff
appendInfoLine: ""

# === Convert to mono ===
selectObject: sound
numCh = Get number of channels
if numCh > 1
    Convert to mono
    monoID = selected("Sound")
else
    Copy: "mono_work"
    monoID = selected("Sound")
endif

# === Calculate chunks ===
numChunks = ceiling(duration / chunk_duration)
appendInfoLine: "Processing ", numChunks, " chunks..."

# === Setup trajectory storage for visualization ===
if draw_visualization
    maxTrajPoints = 200
    trajStep = max(1, floor(numChunks / maxTrajPoints))
    trajIdx = 0
endif

# === Create output channel accumulators ===
for sp from 1 to numSpeakers
    spkSound[sp] = 0
endfor

# === Process chunks ===
for chunk from 1 to numChunks
    chunkStart = (chunk - 1) * chunk_duration
    chunkEnd = min(chunkStart + chunk_duration, duration)
    chunkMid = (chunkStart + chunkEnd) / 2
    progress = chunkMid / duration
    
    # Calculate source position based on movement type
    if movement_type = 1
        # Linear
        srcX = start_x + (end_x - start_x) * progress
        srcY = start_y + (end_y - start_y) * progress
    elsif movement_type = 2
        # Circular
        angle = progress * 2 * pi * speed
        srcX = radius * cos(angle)
        srcY = radius * sin(angle)
    elsif movement_type = 3
        # Figure-8
        angle = progress * 4 * pi * speed
        srcX = radius * sin(angle)
        srcY = radius * sin(2 * angle) / 2
    elsif movement_type = 4
        # Spiral In
        angle = progress * 4 * pi * speed
        curRadius = radius * (1 - progress)
        srcX = curRadius * cos(angle)
        srcY = curRadius * sin(angle)
    elsif movement_type = 5
        # Spiral Out
        angle = progress * 4 * pi * speed
        curRadius = radius * progress
        srcX = curRadius * cos(angle)
        srcY = curRadius * sin(angle)
    elsif movement_type = 6
        # Pendulum
        swingAngle = sin(progress * pi * speed * 4) * pi / 3
        srcX = radius * sin(swingAngle)
        srcY = -radius * cos(swingAngle) * 0.5
    elsif movement_type = 7
        # Zigzag
        numZigs = 4 * speed
        zigProgress = (progress * numZigs) mod 1
        zigNum = floor(progress * numZigs)
        if (zigNum mod 2) = 0
            srcX = -radius + 2 * radius * zigProgress
        else
            srcX = radius - 2 * radius * zigProgress
        endif
        srcY = -radius + 2 * radius * progress
    elsif movement_type = 8
        # Random Walk (golden angle based)
        angle1 = progress * 137.5 * speed
        angle2 = progress * 97.3 * speed
        srcX = radius * sin(angle1) * 0.7
        srcY = radius * cos(angle2) * 0.7
    elsif movement_type = 9
        # Ellipse
        angle = progress * 2 * pi * speed
        srcX = radius * 1.4 * cos(angle)
        srcY = radius * 0.7 * sin(angle)
    else
        # Square
        sideProgress = (progress * 4 * speed) mod 1
        sideNum = floor((progress * 4 * speed) mod 4)
        if sideNum = 0
            srcX = -radius + 2 * radius * sideProgress
            srcY = radius
        elsif sideNum = 1
            srcX = radius
            srcY = radius - 2 * radius * sideProgress
        elsif sideNum = 2
            srcX = radius - 2 * radius * sideProgress
            srcY = -radius
        else
            srcX = -radius
            srcY = -radius + 2 * radius * sideProgress
        endif
    endif
    
    # Store trajectory point (with bounds check)
    if draw_visualization
        if (chunk mod trajStep) = 0 or chunk = 1
            if trajIdx < 200
                trajIdx = trajIdx + 1
                trajX[trajIdx] = srcX
                trajY[trajIdx] = srcY
            endif
        endif
    endif
    
    # Calculate DBAP gains
    totalPower = 0
    for sp from 1 to numSpeakers
        dx = srcX - spkX[sp]
        dy = srcY - spkY[sp]
        dist = sqrt(dx * dx + dy * dy)
        if dist < 0.01
            dist = 0.01
        endif
        gain[sp] = 1 / (dist ^ rolloff)
        totalPower = totalPower + gain[sp] * gain[sp]
    endfor
    
    # Normalize
    if normalize_gains and totalPower > 0
        norm = sqrt(totalPower)
        for sp from 1 to numSpeakers
            gain[sp] = gain[sp] / norm
        endfor
    endif
    
    # Extract chunk from mono
    selectObject: monoID
    chunkID = Extract part: chunkStart, chunkEnd, "rectangular", 1, "no"
    
    # Apply gain to each channel and concatenate
    for sp from 1 to numSpeakers
        selectObject: chunkID
        Copy: "temp_gained"
        tempID = selected("Sound")
        g = gain[sp]
        Formula: "self * 'g'"
        
        # Concatenate to speaker channel
        if spkSound[sp] = 0
            spkSound[sp] = tempID
        else
            selectObject: spkSound[sp], tempID
            newSound = Concatenate
            removeObject: spkSound[sp], tempID
            spkSound[sp] = newSound
        endif
    endfor
    
    removeObject: chunkID
    
    # Progress
    if (chunk mod 50) = 0 or chunk = numChunks
        pct = chunk / numChunks * 100
        appendInfoLine: "  ", fixed$(pct, 0), "% (pos: ", fixed$(srcX, 2), ", ", fixed$(srcY, 2), ")"
    endif
endfor

# === Combine channels ===
appendInfoLine: ""
appendInfoLine: "Combining ", numSpeakers, " channels..."

selectObject: spkSound[1]
for sp from 2 to numSpeakers
    plusObject: spkSound[sp]
endfor
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: soundName$ + "_DBAP_" + movementName$ + "_" + configName$

# === Cleanup ===
removeObject: monoID
for sp from 1 to numSpeakers
    removeObject: spkSound[sp]
endfor

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "DBAP: " + movementName$ + " | " + configName$ + " | " + soundName$
    
    # Speaker layout with trajectory
    Select outer viewport: 0.5, 5.5, 0.8, 5.0
    Select inner viewport: 0.8, 5.2, 1.1, 4.7
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Draw trajectory (with bounds check)
    maxTraj = min(trajIdx, 200)
    if maxTraj > 1
        Line width: 2
        for i from 2 to maxTraj
            # Color gradient (blue to red)
            prog = i / maxTraj
            rCol = prog
            bCol = 1 - prog
            Colour: "{" + fixed$(rCol, 2) + ", 0.3, " + fixed$(bCol, 2) + "}"
            i1 = i - 1
            Draw line: trajX[i1], trajY[i1], trajX[i], trajY[i]
        endfor
        Line width: 1
    endif
    
    # Draw speakers
    for sp from 1 to numSpeakers
        Paint circle (mm): "{0.3, 0.5, 0.7}", spkX[sp], spkY[sp], 4
        Colour: "White"
        Font size: 6
        Text: spkX[sp], "centre", spkY[sp], "half", string$(sp)
    endfor
    
    # Listener at center
    Paint circle (mm): "{0.2, 0.6, 0.3}", 0, 0, 3
    
    # Start/end markers
    if maxTraj > 0
        Paint circle (mm): "{0.2, 0.5, 0.8}", trajX[1], trajY[1], 2
        Font size: 5
        Colour: "Black"
        Text: trajX[1] + 0.1, "left", trajY[1], "half", "Start"
        
        Paint circle (mm): "{0.8, 0.3, 0.3}", trajX[maxTraj], trajY[maxTraj], 2
        Text: trajX[maxTraj] + 0.1, "left", trajY[maxTraj], "half", "End"
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Movement Path & Speakers"
    
    # Parameters
    Select outer viewport: 5.7, 9.5, 0.8, 2.8
    Select inner viewport: 5.9, 9.3, 1.0, 2.6
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.85, "half", "Movement: " + movementName$
    Text: 0.5, "centre", 0.65, "half", "Speakers: " + string$(numSpeakers) + " (" + configName$ + ")"
    Text: 0.5, "centre", 0.45, "half", "Speed: " + fixed$(speed, 1) + " | Radius: " + fixed$(radius, 2)
    Text: 0.5, "centre", 0.25, "half", "Rolloff: " + fixed$(rolloff, 1)
    
    Draw inner box
    
    # Output waveform
    Select outer viewport: 5.7, 9.5, 3.0, 5.0
    Select inner viewport: 5.9, 9.3, 3.2, 4.8
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
appendInfoLine: "Output: ", selected$("Sound"), " (", numSpeakers, " channels)"

if play_result
    selectObject: result
    Play
endif

selectObject: result