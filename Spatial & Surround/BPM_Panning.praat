# ============================================================
# Praat AudioTools - BPM_Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   BPM-synced creative stereo panning effects.
#   Cycles parameter controls panning speed relative to file duration.
#
# Changelog v0.2:
#   - Added input validation
#   - Auto-convert mono to stereo
#   - Fixed ID-based selection
#   - Added visualization
#   - Added play toggle
# ============================================================

form BPM Stereo Panning
    comment === SPEED (cycles per file duration) ===
    optionmenu Cycles: 4
        option: "1 cycle (very slow)"
        option: "2 cycles"
        option: "4 cycles"
        option: "8 cycles (medium)"
        option: "16 cycles"
        option: "32 cycles (fast)"
        option: "64 cycles (very fast)"
    
    comment === PANNING PATTERN ===
    optionmenu Pattern: 1
        option: "1. Spiral (accelerating)"
        option: "2. Wobble (drunk walking)"
        option: "3. Heartbeat (organic pulse)"
        option: "4. Pendulum (decaying swing)"
        option: "5. Glitch (chaotic jumps)"
        option: "6. Doppler (racing car)"
        option: "7. Breathing (inhale/exhale)"
        option: "8. Lightning (chaotic strikes)"
        option: "9. Orbit (elliptical)"
        option: "10. Tsunami (building wave)"
        option: "11. Fractal (multi-scale)"
        option: "12. Neural (brain waves)"
        option: "13. Quantum (probability)"
        option: "14. Virus (spreading chaos)"
        option: "15. DNA (double helix)"
    
    comment === OUTPUT ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
numCh = Get number of channels
duration = Get total duration
sr = Get sampling frequency

# === Convert mono to stereo if needed ===
if numCh = 1
    Convert to stereo
    workID = selected("Sound")
elsif numCh = 2
    Copy: "work_copy"
    workID = selected("Sound")
else
    exitScript: "Please use mono or stereo source."
endif

# === Calculate cycles ===
if cycles = 1
    numCycles = 1
elsif cycles = 2
    numCycles = 2
elsif cycles = 3
    numCycles = 4
elsif cycles = 4
    numCycles = 8
elsif cycles = 5
    numCycles = 16
elsif cycles = 6
    numCycles = 32
else
    numCycles = 64
endif

baseRate = numCycles / duration
br$ = string$(baseRate)
dur$ = string$(duration)

# === Pattern names ===
patternNames$[1] = "Spiral"
patternNames$[2] = "Wobble"
patternNames$[3] = "Heartbeat"
patternNames$[4] = "Pendulum"
patternNames$[5] = "Glitch"
patternNames$[6] = "Doppler"
patternNames$[7] = "Breathing"
patternNames$[8] = "Lightning"
patternNames$[9] = "Orbit"
patternNames$[10] = "Tsunami"
patternNames$[11] = "Fractal"
patternNames$[12] = "Neural"
patternNames$[13] = "Quantum"
patternNames$[14] = "Virus"
patternNames$[15] = "DNA"
patternName$ = patternNames$[pattern]

# === Info ===
writeInfoLine: "=== BPM Stereo Panning ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), "s"
appendInfoLine: "Cycles: ", numCycles, " (", fixed$(baseRate, 2), " Hz)"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: ""

# === Extract channels ===
selectObject: workID
Extract one channel: 1
leftID = selected("Sound")

selectObject: workID
Extract one channel: 2
rightID = selected("Sound")

# === Apply panning pattern ===
if pattern = 1
    # SPIRAL - Accelerating circular motion
    selectObject: leftID
    Formula: "self * (0.5 - 0.4 * sin(2*pi*'br$'*x*x/'dur$'))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.4 * sin(2*pi*'br$'*x*x/'dur$'))"

elsif pattern = 2
    # WOBBLE - Drunk walking
    selectObject: leftID
    Formula: "self * (0.5 - 0.35 * sin(2*pi*'br$'*x) - 0.15 * sin(7*pi*'br$'*x))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.35 * sin(2*pi*'br$'*x) + 0.15 * sin(7*pi*'br$'*x))"

elsif pattern = 3
    # HEARTBEAT - Organic double-thump
    selectObject: leftID
    Formula: "self * (0.5 - 0.4 * (sin(4*pi*'br$'*x) * exp(-20*((2*'br$'*x) mod 1 - 0.5)^2)))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.4 * (sin(4*pi*'br$'*x) * exp(-20*((2*'br$'*x) mod 1 - 0.5)^2)))"

elsif pattern = 4
    # PENDULUM - Decaying swing
    selectObject: leftID
    Formula: "self * (0.5 - 0.45 * sin(2*pi*'br$'*x) * exp(-0.1*'br$'*x))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.45 * sin(2*pi*'br$'*x) * exp(-0.1*'br$'*x))"

elsif pattern = 5
    # GLITCH - Chaotic jumps
    selectObject: leftID
    Formula: "self * max(0.05, min(0.95, 0.5 - 0.4 * sin(23*pi*'br$'*x) * sin(7*pi*'br$'*x)))"
    selectObject: rightID
    Formula: "self * max(0.05, min(0.95, 0.5 + 0.4 * sin(23*pi*'br$'*x) * sin(7*pi*'br$'*x)))"

elsif pattern = 6
    # DOPPLER - Racing car
    selectObject: leftID
    Formula: "self * (0.5 - 0.4 * sin(2*pi*'br$'*x + 10*sin(0.5*pi*'br$'*x)))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.4 * sin(2*pi*'br$'*x + 10*sin(0.5*pi*'br$'*x)))"

elsif pattern = 7
    # BREATHING - Inhale/exhale
    selectObject: leftID
    Formula: "self * (0.5 - 0.3 * (sin(pi*'br$'*x))^3)"
    selectObject: rightID
    Formula: "self * (0.5 + 0.3 * (sin(pi*'br$'*x))^3)"

elsif pattern = 8
    # LIGHTNING - Chaotic strikes
    selectObject: leftID
    Formula: "self * (0.5 - 0.3 * sin(2*pi*'br$'*x) - 0.2 * sin(13*pi*'br$'*x) - 0.1 * sin(29*pi*'br$'*x))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.3 * sin(2*pi*'br$'*x) + 0.2 * sin(13*pi*'br$'*x) + 0.1 * sin(29*pi*'br$'*x))"

elsif pattern = 9
    # ORBIT - Elliptical motion
    selectObject: leftID
    Formula: "self * (0.5 - 0.4 * sin(2*pi*'br$'*x) - 0.2 * sin(4*pi*'br$'*x))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.4 * sin(2*pi*'br$'*x) + 0.2 * sin(4*pi*'br$'*x))"

elsif pattern = 10
    # TSUNAMI - Building wave
    selectObject: leftID
    Formula: "self * (0.5 - 0.4 * sin(2*pi*'br$'*x) * (x/'dur$'))"
    selectObject: rightID
    Formula: "self * (0.5 + 0.4 * sin(2*pi*'br$'*x) * (x/'dur$'))"

elsif pattern = 11
    # FRACTAL - Multi-scale chaos
    selectObject: leftID
    Formula: "self * max(0.1, min(0.9, 0.5 - 0.3 * sin(2*pi*'br$'*x) * sin(8*pi*'br$'*x) * sin(32*pi*'br$'*x)))"
    selectObject: rightID
    Formula: "self * max(0.1, min(0.9, 0.5 + 0.3 * sin(2*pi*'br$'*x) * sin(8*pi*'br$'*x) * sin(32*pi*'br$'*x)))"

elsif pattern = 12
    # NEURAL - Brain waves (tanh approximation)
    selectObject: leftID
    Formula: "self * max(0.05, min(0.95, 0.5 - 0.4 * (3*sin(2*pi*'br$'*x + 2*sin(5*pi*'br$'*x)))/(1 + abs(3*sin(2*pi*'br$'*x + 2*sin(5*pi*'br$'*x))))))"
    selectObject: rightID
    Formula: "self * max(0.05, min(0.95, 0.5 + 0.4 * (3*sin(2*pi*'br$'*x + 2*sin(5*pi*'br$'*x)))/(1 + abs(3*sin(2*pi*'br$'*x + 2*sin(5*pi*'br$'*x))))))"

elsif pattern = 13
    # QUANTUM - Probability waves
    selectObject: leftID
    Formula: "self * max(0.05, min(0.95, 0.5 - 0.4 * (sin(2*pi*'br$'*x))^3 * (cos(3*pi*'br$'*x))^2))"
    selectObject: rightID
    Formula: "self * max(0.05, min(0.95, 0.5 + 0.4 * (sin(2*pi*'br$'*x))^3 * (cos(3*pi*'br$'*x))^2))"

elsif pattern = 14
    # VIRUS - Spreading chaos
    selectObject: leftID
    Formula: "self * max(0.05, min(0.95, 0.5 - 0.35 * sin(11*pi*'br$'*x) * sin(17*pi*'br$'*x) * exp(-((2*'br$'*x) mod 4 - 2)^2)))"
    selectObject: rightID
    Formula: "self * max(0.05, min(0.95, 0.5 + 0.35 * sin(11*pi*'br$'*x) * sin(17*pi*'br$'*x) * exp(-((2*'br$'*x) mod 4 - 2)^2)))"

else
    # DNA - Double helix (pattern 15)
    selectObject: leftID
    Formula: "self * max(0.1, min(0.9, 0.5 - 0.3 * (sin(2*pi*'br$'*x) * (0.7 + 0.3 * sin(0.5*pi*'br$'*x)) + 0.2 * sin(2*pi*'br$'*x + pi/2))))"
    selectObject: rightID
    Formula: "self * max(0.1, min(0.9, 0.5 + 0.3 * (sin(2*pi*'br$'*x) * (0.7 + 0.3 * sin(0.5*pi*'br$'*x)) + 0.2 * sin(2*pi*'br$'*x + pi/2))))"
endif

# === Combine channels ===
selectObject: leftID, rightID
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: originalName$ + "_pan_" + patternName$

# === Cleanup ===
removeObject: workID, leftID, rightID

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "BPM Stereo Panning: " + patternName$ + " (" + string$(numCycles) + " cycles) | " + originalName$
    
    # Pan position over time
    Select outer viewport: 0.5, 9.5, 0.8, 3.5
    Select inner viewport: 1.0, 9.0, 1.2, 3.2
    
    Axes: 0, duration, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, -1.2, 1.2
    
    # Center line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    
    # Draw pan curve (sample at 200 points)
    Line width: 2
    Colour: "{0.3, 0.5, 0.8}"
    
    for i from 0 to 199
        t1 = i * duration / 200
        t2 = (i + 1) * duration / 200
        
        # Calculate pan position based on pattern
        if pattern = 1
            # Spiral
            p1 = sin(2*pi*baseRate*t1*t1/duration)
            p2 = sin(2*pi*baseRate*t2*t2/duration)
        elsif pattern = 2
            # Wobble
            p1 = 0.7 * sin(2*pi*baseRate*t1) + 0.3 * sin(7*pi*baseRate*t1)
            p2 = 0.7 * sin(2*pi*baseRate*t2) + 0.3 * sin(7*pi*baseRate*t2)
        elsif pattern = 7
            # Breathing
            p1 = (sin(pi*baseRate*t1))^3
            p2 = (sin(pi*baseRate*t2))^3
        elsif pattern = 10
            # Tsunami
            p1 = sin(2*pi*baseRate*t1) * (t1/duration)
            p2 = sin(2*pi*baseRate*t2) * (t2/duration)
        else
            # Default sine
            p1 = sin(2*pi*baseRate*t1)
            p2 = sin(2*pi*baseRate*t2)
        endif
        
        Draw line: t1, p1, t2, p2
    endfor
    
    Line width: 1
    
    # Labels
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Pan (L/R)"
    Font size: 7
    Text: duration * 0.02, "left", 1.0, "half", "Right"
    Text: duration * 0.02, "left", -1.0, "half", "Left"
    
    # Pattern info box
    Select outer viewport: 0.5, 4.5, 3.7, 5.5
    Select inner viewport: 0.7, 4.3, 3.9, 5.3
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.8, "half", "Pattern: " + patternName$
    Text: 0.5, "centre", 0.55, "half", "Cycles: " + string$(numCycles)
    Text: 0.5, "centre", 0.3, "half", "Rate: " + fixed$(baseRate, 2) + " Hz"
    
    Draw inner box
    
    # Output waveform
    Select outer viewport: 4.7, 9.5, 3.7, 5.5
    Select inner viewport: 4.9, 9.3, 3.9, 5.3
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
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result