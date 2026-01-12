# ============================================================
# Praat AudioTools - 8-Channel_Movements.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Spatial Movement Generator
#   Creates spatial movement patterns by automating volume
#   across 8 channels using IntensityTiers.
#
# Changelog v0.2:
#   - Renamed form to match script purpose
#   - Added visualization of movement pattern
#   - Added play toggle
#   - Added input validation
#   - Organized parameters by category
# ============================================================

form 8-Channel Spatial Movements
    comment === MOVEMENT PATTERN ===
    optionmenu Pattern: 8
        option: "1. Sine wave (volume oscillation)"
        option: "2. Fade in"
        option: "3. Fade out"
        option: "4. Triangle envelope"
        option: "5. Constant value"
        option: "6. Exponential fade"
        option: "7. Linear sweep (L to R)"
        option: "8. Circular rotation"
        option: "9. Figure-8 pattern"
        option: "10. Random walk"
        option: "11. Spiral motion"
        option: "12. Custom position"
    
    comment === TIMING PARAMETERS ===
    positive Motion_speed 1.0
    positive Frequency_hz 2.0
    positive Fadein_time 1.0
    
    comment === VOLUME PARAMETERS ===
    positive Min_volume 30.0
    positive Max_volume 100.0
    positive Amplitude 50.0
    positive Exponent 1.0
    
    comment === CUSTOM POSITION (pattern 12 only) ===
    real Custom_x 0.5
    real Custom_y 0.5
    
    comment === QUALITY ===
    positive Number_of_points 100
    integer Random_seed 1
    
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
duration = Get total duration

# === Pattern name for output ===
if pattern = 1
    patternName$ = "SineWave"
elsif pattern = 2
    patternName$ = "FadeIn"
elsif pattern = 3
    patternName$ = "FadeOut"
elsif pattern = 4
    patternName$ = "Triangle"
elsif pattern = 5
    patternName$ = "Constant"
elsif pattern = 6
    patternName$ = "Exponential"
elsif pattern = 7
    patternName$ = "LinearSweep"
elsif pattern = 8
    patternName$ = "Circular"
elsif pattern = 9
    patternName$ = "Figure8"
elsif pattern = 10
    patternName$ = "RandomWalk"
elsif pattern = 11
    patternName$ = "Spiral"
else
    patternName$ = "CustomPos"
endif

# === Info ===
writeInfoLine: "=== 8-Channel Spatial Movements ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 2), "s"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: ""

# === Create 8 mono channels ===
selectObject: sound
for ch from 1 to 8
    selectObject: sound
    channel[ch] = Copy: "ch" + string$(ch)
endfor

# === Create 8 IntensityTiers ===
for ch from 1 to 8
    intensityTier[ch] = Create IntensityTier: "int" + string$(ch), 0, duration
    selectObject: intensityTier[ch]
    for i from 0 to number_of_points
        time = i * duration / number_of_points
        Add point: time, 70.0
    endfor
endfor

# === Apply movement formulas ===
volRange = max_volume - min_volume

if pattern = 7
    # Linear sweep around 8 channels
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        peakTime = (ch - 1) / 8
        Formula: string$(min_volume) + " + " + string$(volRange) + " * exp(-10 * ((x/" + string$(duration) + ") - " + string$(peakTime) + ")^2)"
    endfor
    
elsif pattern = 8
    # Circular rotation around 8 channels
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        angle = (ch - 1) * 45
        Formula: string$(min_volume) + " + " + string$(volRange / 2) + " * (1 + cos(2*pi*" + string$(motion_speed) + "*x - " + string$(angle * pi / 180) + "))"
    endfor
    
elsif pattern = 9
    # Figure-8 pattern across 8 channels
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        angle = (ch - 1) * 45
        Formula: string$(min_volume) + " + " + string$(volRange / 2) + " * (1 + sin(4*pi*" + string$(motion_speed) + "*x + " + string$(angle * pi / 180) + "))"
    endfor
    
elsif pattern = 10
    # Random walk across 8 channels
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        phase = random_seed + ch * 1.234
        Formula: string$(min_volume) + " + " + string$(volRange / 2) + " * (1 + sin(" + string$(phase) + " + x*" + string$(motion_speed * 10) + "))"
    endfor
    
elsif pattern = 11
    # Spiral motion across 8 channels
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        angle = (ch - 1) * 45
        Formula: string$(min_volume) + " + " + string$(volRange / 2) + " * (1 + (x/" + string$(duration) + ") * sin(2*pi*" + string$(motion_speed) + "*x + " + string$(angle * pi / 180) + "))"
    endfor
    
elsif pattern = 12
    # Custom position - focus on specific channels based on x,y coordinates
    # Channel positions (octagon layout)
    posX[1] = 0.25
    posY[1] = 0.25
    posX[2] = 0.50
    posY[2] = 0.15
    posX[3] = 0.75
    posY[3] = 0.25
    posX[4] = 0.85
    posY[4] = 0.50
    posX[5] = 0.75
    posY[5] = 0.75
    posX[6] = 0.50
    posY[6] = 0.85
    posX[7] = 0.25
    posY[7] = 0.75
    posX[8] = 0.15
    posY[8] = 0.50
    
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        dist = sqrt((custom_x - posX[ch])^2 + (custom_y - posY[ch])^2)
        volume = min_volume + volRange * exp(-dist * 10)
        Formula: string$(volume)
    endfor
    
else
    # Non-spatial effects (same formula for all channels)
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        if pattern = 1
            Formula: string$(amplitude + 50) + " + " + string$(amplitude) + "*sin(2*pi*" + string$(frequency_hz) + "*x)"
        elsif pattern = 2
            Formula: "if x < " + string$(fadein_time) + " then " + string$(max_volume) + " * (x/" + string$(fadein_time) + ") else " + string$(max_volume) + " endif"
        elsif pattern = 3
            Formula: string$(max_volume) + " * (1 - (x/" + string$(duration) + "))"
        elsif pattern = 4
            Formula: string$(max_volume) + " * (1 - 2*abs(x/" + string$(duration) + " - 0.5))"
        elsif pattern = 5
            Formula: string$(max_volume)
        elsif pattern = 6
            Formula: string$(max_volume) + " * exp(-" + string$(exponent) + "*x)"
        endif
    endfor
endif

# === Multiply each channel with its IntensityTier ===
for ch from 1 to 8
    selectObject: channel[ch], intensityTier[ch]
    result[ch] = Multiply: "yes"
endfor

# === Combine all 8 channels ===
selectObject: result[1], result[2], result[3], result[4], result[5], result[6], result[7], result[8]
resultSound = Combine to stereo
Scale peak: 0.95
Rename: soundName$ + "_8chMove_" + patternName$

# === Cleanup ===
for ch from 1 to 8
    removeObject: channel[ch], intensityTier[ch], result[ch]
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
    Text: 0.5, "centre", 0.5, "half", "8-Channel Movement: " + patternName$ + " | " + soundName$
    
    # Spatial layout diagram (top-down view)
    Select outer viewport: 0.5, 5.0, 0.8, 4.5
    Select inner viewport: 0.8, 4.7, 1.1, 4.2
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    # Draw 8 speakers using Paint circle (mm)
    # Channel 1 - Front-Left
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.25, 0.75, 4
    Colour: "White"
    Font size: 7
    Text: 0.25, "centre", 0.75, "half", "1"
    
    # Channel 2 - Front
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.50, 0.90, 4
    Colour: "White"
    Text: 0.50, "centre", 0.90, "half", "2"
    
    # Channel 3 - Front-Right
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.75, 0.75, 4
    Colour: "White"
    Text: 0.75, "centre", 0.75, "half", "3"
    
    # Channel 4 - Right
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.90, 0.50, 4
    Colour: "White"
    Text: 0.90, "centre", 0.50, "half", "4"
    
    # Channel 5 - Back-Right
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.75, 0.25, 4
    Colour: "White"
    Text: 0.75, "centre", 0.25, "half", "5"
    
    # Channel 6 - Back
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.50, 0.10, 4
    Colour: "White"
    Text: 0.50, "centre", 0.10, "half", "6"
    
    # Channel 7 - Back-Left
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.25, 0.25, 4
    Colour: "White"
    Text: 0.25, "centre", 0.25, "half", "7"
    
    # Channel 8 - Left
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.10, 0.50, 4
    Colour: "White"
    Text: 0.10, "centre", 0.50, "half", "8"
    
    # Listener at center
    Paint circle (mm): "{0.2, 0.6, 0.3}", 0.5, 0.5, 3
    Colour: "White"
    Font size: 6
    Text: 0.5, "centre", 0.5, "half", "L"
    
    # Draw movement pattern
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    if pattern = 8
        # Circular - draw path (24 segments)
        for degStep from 0 to 23
            deg = degStep * 15
            deg2 = deg + 15
            rad1 = deg * pi / 180
            rad2 = deg2 * pi / 180
            cx1 = 0.5 + 0.3 * cos(rad1)
            cy1 = 0.5 + 0.3 * sin(rad1)
            cx2 = 0.5 + 0.3 * cos(rad2)
            cy2 = 0.5 + 0.3 * sin(rad2)
            Draw line: cx1, cy1, cx2, cy2
        endfor
    elsif pattern = 9
        # Figure-8 (20 segments)
        for tStep from 0 to 19
            t = tStep * 5
            t2 = t + 5
            ang1 = t * 2 * pi / 100
            ang2 = t2 * 2 * pi / 100
            fx1 = 0.5 + 0.25 * sin(ang1)
            fy1 = 0.5 + 0.2 * sin(2 * ang1)
            fx2 = 0.5 + 0.25 * sin(ang2)
            fy2 = 0.5 + 0.2 * sin(2 * ang2)
            Draw line: fx1, fy1, fx2, fy2
        endfor
    elsif pattern = 7
        # Linear sweep - arrow
        Draw arrow: 0.15, 0.5, 0.85, 0.5
    elsif pattern = 12
        # Custom position
        Paint circle (mm): "{0.9, 0.2, 0.2}", custom_x, custom_y, 4
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Speaker Layout"
    
    # Channel intensity curves
    Select outer viewport: 5.2, 9.5, 0.8, 4.5
    Select inner viewport: 5.5, 9.2, 1.1, 4.2
    
    Axes: 0, duration, 0, 110
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 110
    
    # Draw curves for channels 1-4
    Line width: 2
    
    # Channel 1 - Red
    Colour: "{0.8, 0.2, 0.2}"
    for i from 0 to 49
        i2 = i + 1
        t1 = i * duration / 50
        t2 = i2 * duration / 50
        if pattern = 8
            angRad = 0
            v1 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t1 - angRad))
            v2 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t2 - angRad))
        elsif pattern = 7
            pk = 0
            d1 = t1/duration - pk
            d2 = t2/duration - pk
            v1 = min_volume + volRange * exp(-10 * d1 * d1)
            v2 = min_volume + volRange * exp(-10 * d2 * d2)
        else
            v1 = 70
            v2 = 70
        endif
        Draw line: t1, v1, t2, v2
    endfor
    
    # Channel 2 - Green
    Colour: "{0.2, 0.6, 0.2}"
    for i from 0 to 49
        i2 = i + 1
        t1 = i * duration / 50
        t2 = i2 * duration / 50
        if pattern = 8
            angRad = 45 * pi / 180
            v1 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t1 - angRad))
            v2 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t2 - angRad))
        elsif pattern = 7
            pk = 0.125
            d1 = t1/duration - pk
            d2 = t2/duration - pk
            v1 = min_volume + volRange * exp(-10 * d1 * d1)
            v2 = min_volume + volRange * exp(-10 * d2 * d2)
        else
            v1 = 70
            v2 = 70
        endif
        Draw line: t1, v1, t2, v2
    endfor
    
    # Channel 3 - Blue
    Colour: "{0.2, 0.2, 0.8}"
    for i from 0 to 49
        i2 = i + 1
        t1 = i * duration / 50
        t2 = i2 * duration / 50
        if pattern = 8
            angRad = 90 * pi / 180
            v1 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t1 - angRad))
            v2 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t2 - angRad))
        elsif pattern = 7
            pk = 0.25
            d1 = t1/duration - pk
            d2 = t2/duration - pk
            v1 = min_volume + volRange * exp(-10 * d1 * d1)
            v2 = min_volume + volRange * exp(-10 * d2 * d2)
        else
            v1 = 70
            v2 = 70
        endif
        Draw line: t1, v1, t2, v2
    endfor
    
    # Channel 4 - Orange
    Colour: "{0.7, 0.5, 0.2}"
    for i from 0 to 49
        i2 = i + 1
        t1 = i * duration / 50
        t2 = i2 * duration / 50
        if pattern = 8
            angRad = 135 * pi / 180
            v1 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t1 - angRad))
            v2 = min_volume + (volRange / 2) * (1 + cos(2*pi*motion_speed*t2 - angRad))
        elsif pattern = 7
            pk = 0.375
            d1 = t1/duration - pk
            d2 = t2/duration - pk
            v1 = min_volume + volRange * exp(-10 * d1 * d1)
            v2 = min_volume + volRange * exp(-10 * d2 * d2)
        else
            v1 = 70
            v2 = 70
        endif
        Draw line: t1, v1, t2, v2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Volume"
    
    # Legend
    Font size: 6
    Colour: "{0.8, 0.2, 0.2}"
    Text: duration * 0.85, "left", 105, "half", "Ch1"
    Colour: "{0.2, 0.6, 0.2}"
    Text: duration * 0.85, "left", 97, "half", "Ch2"
    Colour: "{0.2, 0.2, 0.8}"
    Text: duration * 0.85, "left", 89, "half", "Ch3"
    Colour: "{0.7, 0.5, 0.2}"
    Text: duration * 0.85, "left", 81, "half", "Ch4"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel with ", patternName$, " movement"

if play_result
    selectObject: resultSound
    Play
endif

selectObject: resultSound