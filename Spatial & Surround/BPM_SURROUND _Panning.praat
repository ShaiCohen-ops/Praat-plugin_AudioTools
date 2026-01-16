# ============================================================
# Praat AudioTools - BPM_SURROUND_Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel BPM-synced surround panning with creative spatial patterns.
#   Uses 7.1 speaker layout with time-varying amplitude modulation.
#
# Changelog v0.2:
#   - Added input validation
#   - Implemented all 15 patterns
#   - Fixed ID-based selection
#   - Fixed binaural downmix
#   - Added visualization
#   - Added play toggle
#   - Combined to actual 8-channel output
# ============================================================

form BPM Surround Panning
    comment === SPEED (cycles per file duration) ===
    optionmenu Cycles: 4
        option: "1 cycle (very slow)"
        option: "2 cycles"
        option: "4 cycles"
        option: "8 cycles (medium)"
        option: "16 cycles"
        option: "32 cycles (fast)"
        option: "64 cycles (very fast)"
    
    comment === SPATIAL PATTERN ===
    optionmenu Pattern: 1
        option: "1. Circle (clockwise orbit)"
        option: "2. Figure-8 (infinity loop)"
        option: "3. Spiral (expanding)"
        option: "4. Bounce (wall collision)"
        option: "5. Swarm (bee movement)"
        option: "6. Tornado (vortex)"
        option: "7. Wave (ocean current)"
        option: "8. Plasma (energy field)"
        option: "9. Neural (brain network)"
        option: "10. Quantum (probability cloud)"
        option: "11. DNA (double helix)"
        option: "12. Galaxy (stellar motion)"
        option: "13. Lightning (discharge)"
        option: "14. Heartbeat (pulse)"
        option: "15. Breathing (expansion)"
    
    comment === OUTPUT ===
    boolean Create_8ch_combined 1
    boolean Create_binaural_mix 1
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
if numCh > 2
    exitScript: "Please use mono or stereo source."
endif

# Convert to mono
if numCh = 2
    Convert to mono
    monoID = selected("Sound")
else
    Copy: "mono_work"
    monoID = selected("Sound")
endif

selectObject: monoID
duration = Get total duration
sr = Get sampling frequency

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

# === Pattern name ===
patternNames$[1] = "Circle"
patternNames$[2] = "Figure8"
patternNames$[3] = "Spiral"
patternNames$[4] = "Bounce"
patternNames$[5] = "Swarm"
patternNames$[6] = "Tornado"
patternNames$[7] = "Wave"
patternNames$[8] = "Plasma"
patternNames$[9] = "Neural"
patternNames$[10] = "Quantum"
patternNames$[11] = "DNA"
patternNames$[12] = "Galaxy"
patternNames$[13] = "Lightning"
patternNames$[14] = "Heartbeat"
patternNames$[15] = "Breathing"
patternName$ = patternNames$[pattern]

# === Info ===
writeInfoLine: "=== BPM Surround Panning ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), "s"
appendInfoLine: "Cycles: ", numCycles, " (", fixed$(baseRate, 2), " Hz)"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: ""
appendInfoLine: "Speaker layout: 7.1 Surround"
appendInfoLine: "  1-FL  2-FR  3-C  4-LFE"
appendInfoLine: "  5-SL  6-SR  7-BL  8-BR"
appendInfoLine: ""

# === Create 8 channel copies ===
for ch from 1 to 8
    selectObject: monoID
    Copy: "ch" + string$(ch)
    channel[ch] = selected("Sound")
endfor

# === Channel labels ===
chLabel$[1] = "FL"
chLabel$[2] = "FR"
chLabel$[3] = "C"
chLabel$[4] = "LFE"
chLabel$[5] = "SL"
chLabel$[6] = "SR"
chLabel$[7] = "BL"
chLabel$[8] = "BR"

# === Speaker angles (for visualization) ===
spkAngle[1] = 330
spkAngle[2] = 30
spkAngle[3] = 0
spkAngle[4] = 180
spkAngle[5] = 250
spkAngle[6] = 110
spkAngle[7] = 210
spkAngle[8] = 150

# === Apply spatial pattern ===
br$ = string$(baseRate)

if pattern = 1
    # CIRCLE - Clockwise orbit
    selectObject: channel[1]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x - 5*pi/4)))"
    selectObject: channel[2]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x - pi/4)))"
    selectObject: channel[3]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x)))"
    selectObject: channel[4]
    Formula: "self * 0.3"
    selectObject: channel[5]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x - 3*pi/2)))"
    selectObject: channel[6]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x - pi/2)))"
    selectObject: channel[7]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x - 7*pi/4)))"
    selectObject: channel[8]
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*'br$'*x - 3*pi/4)))"

elsif pattern = 2
    # FIGURE-8 - Infinity loop
    selectObject: channel[1]
    Formula: "self * max(0.05, (0.5 + 0.4 * sin(2*pi*'br$'*x) * cos(4*pi*'br$'*x)))"
    selectObject: channel[2]
    Formula: "self * max(0.05, (0.5 - 0.4 * sin(2*pi*'br$'*x) * cos(4*pi*'br$'*x)))"
    selectObject: channel[3]
    Formula: "self * max(0.05, (0.5 + 0.3 * sin(4*pi*'br$'*x)))"
    selectObject: channel[4]
    Formula: "self * (0.2 + 0.1 * abs(sin(2*pi*'br$'*x)))"
    selectObject: channel[5]
    Formula: "self * max(0.05, (0.5 - 0.4 * sin(2*pi*'br$'*x) * cos(4*pi*'br$'*x)))"
    selectObject: channel[6]
    Formula: "self * max(0.05, (0.5 + 0.4 * sin(2*pi*'br$'*x) * cos(4*pi*'br$'*x)))"
    selectObject: channel[7]
    Formula: "self * max(0.05, (0.5 - 0.3 * sin(4*pi*'br$'*x)))"
    selectObject: channel[8]
    Formula: "self * max(0.05, (0.5 - 0.3 * sin(4*pi*'br$'*x)))"

elsif pattern = 3
    # SPIRAL - Expanding/contracting
    selectObject: channel[1]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x - 5*pi/4)))"
    selectObject: channel[2]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x - pi/4)))"
    selectObject: channel[3]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x)))"
    selectObject: channel[4]
    Formula: "self * (0.4 - 0.1 * (0.3 + 0.2 * sin(0.5*pi*'br$'*x)))"
    selectObject: channel[5]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x - 3*pi/2)))"
    selectObject: channel[6]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x - pi/2)))"
    selectObject: channel[7]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x - 7*pi/4)))"
    selectObject: channel[8]
    Formula: "self * max(0.05, (0.5 + (0.3 + 0.2 * sin(0.5*pi*'br$'*x)) * cos(4*pi*'br$'*x - 3*pi/4)))"

elsif pattern = 4
    # BOUNCE - Wall collisions
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.3 * (abs((4*'br$'*x) mod 4 - 2) - 1) - 0.2 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 - 0.3 * (abs((4*'br$'*x) mod 4 - 2) - 1) - 0.2 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 - 0.4 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"
    selectObject: channel[4]
    Formula: "self * (0.3 + 0.1 * abs(abs((4*'br$'*x) mod 4 - 2) - 1))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.3 * (abs((4*'br$'*x) mod 4 - 2) - 1) + 0.2 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 - 0.3 * (abs((4*'br$'*x) mod 4 - 2) - 1) + 0.2 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.4 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.4 * (abs((3*'br$'*x) mod 6 - 3) - 1.5))"

elsif pattern = 5
    # SWARM - Bee movement
    selectObject: channel[1]
    Formula: "self * max(0.05, min(0.9, 0.5 + 0.25 * sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x) + 0.15 * sin(5*pi*'br$'*x) * sin(11*pi*'br$'*x)))"
    selectObject: channel[2]
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.25 * sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x) + 0.15 * sin(5*pi*'br$'*x) * sin(11*pi*'br$'*x)))"
    selectObject: channel[3]
    Formula: "self * max(0.05, min(0.9, 0.5 + 0.2 * sin(5*pi*'br$'*x) * sin(11*pi*'br$'*x)))"
    selectObject: channel[4]
    Formula: "self * (0.25 + 0.1 * abs(sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x)))"
    selectObject: channel[5]
    Formula: "self * max(0.05, min(0.9, 0.5 + 0.25 * sin(5*pi*'br$'*x) * sin(11*pi*'br$'*x) - 0.15 * sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x)))"
    selectObject: channel[6]
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.25 * sin(5*pi*'br$'*x) * sin(11*pi*'br$'*x) - 0.15 * sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x)))"
    selectObject: channel[7]
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.2 * sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x)))"
    selectObject: channel[8]
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.2 * sin(7*pi*'br$'*x) * sin(3*pi*'br$'*x)))"

elsif pattern = 6
    # TORNADO - Vortex
    selectObject: channel[1]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x - 5*pi/4) * (0.7 + 0.3 * sin(pi*'br$'*x))))"
    selectObject: channel[2]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x - pi/4) * (0.7 + 0.3 * sin(pi*'br$'*x))))"
    selectObject: channel[3]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x) * (0.7 + 0.3 * sin(pi*'br$'*x))))"
    selectObject: channel[4]
    Formula: "self * (0.4 - 0.1 * abs(sin(pi*'br$'*x)))"
    selectObject: channel[5]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x - 3*pi/2) * (0.7 - 0.3 * sin(pi*'br$'*x))))"
    selectObject: channel[6]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x - pi/2) * (0.7 - 0.3 * sin(pi*'br$'*x))))"
    selectObject: channel[7]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x - 7*pi/4) * (0.7 - 0.3 * sin(pi*'br$'*x))))"
    selectObject: channel[8]
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(6*pi*'br$'*x - 3*pi/4) * (0.7 - 0.3 * sin(pi*'br$'*x))))"

elsif pattern = 7
    # WAVE - Ocean current
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(2*pi*'br$'*x - pi/4))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(2*pi*'br$'*x + pi/4))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.35 * sin(2*pi*'br$'*x))"
    selectObject: channel[4]
    Formula: "self * (0.3 + 0.15 * sin(pi*'br$'*x))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(2*pi*'br$'*x - 3*pi/4))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(2*pi*'br$'*x + 3*pi/4))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(2*pi*'br$'*x - pi))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(2*pi*'br$'*x + pi))"

elsif pattern = 8
    # PLASMA - Energy field
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.3 * sin(3*pi*'br$'*x) * cos(5*pi*'br$'*x))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.3 * cos(3*pi*'br$'*x) * sin(5*pi*'br$'*x))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.25 * sin(4*pi*'br$'*x))"
    selectObject: channel[4]
    Formula: "self * (0.3 + 0.2 * abs(sin(2*pi*'br$'*x)))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 - 0.3 * sin(3*pi*'br$'*x) * cos(5*pi*'br$'*x))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 - 0.3 * cos(3*pi*'br$'*x) * sin(5*pi*'br$'*x))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.3 * sin(5*pi*'br$'*x) * cos(7*pi*'br$'*x))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.3 * cos(5*pi*'br$'*x) * sin(7*pi*'br$'*x))"

elsif pattern = 9
    # NEURAL - Brain network
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(2*pi*'br$'*x) > 0.3))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(2*pi*'br$'*x + pi/3) > 0.3))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.35 * (sin(3*pi*'br$'*x) > 0.2))"
    selectObject: channel[4]
    Formula: "self * 0.25"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(2*pi*'br$'*x + 2*pi/3) > 0.3))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(2*pi*'br$'*x + pi) > 0.3))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(2*pi*'br$'*x + 4*pi/3) > 0.3))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(2*pi*'br$'*x + 5*pi/3) > 0.3))"

elsif pattern = 10
    # QUANTUM - Probability cloud
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * exp(-((sin(4*pi*'br$'*x))^2)*3))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * exp(-((cos(4*pi*'br$'*x))^2)*3))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.3 * exp(-((sin(6*pi*'br$'*x))^2)*2))"
    selectObject: channel[4]
    Formula: "self * 0.3"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.4 * exp(-((sin(4*pi*'br$'*x + pi/2))^2)*3))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.4 * exp(-((cos(4*pi*'br$'*x + pi/2))^2)*3))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.4 * exp(-((sin(4*pi*'br$'*x + pi))^2)*3))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.4 * exp(-((cos(4*pi*'br$'*x + pi))^2)*3))"

elsif pattern = 11
    # DNA - Double helix
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(4*pi*'br$'*x) * (0.5 + 0.5*sin(pi*'br$'*x)))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(4*pi*'br$'*x + pi) * (0.5 + 0.5*sin(pi*'br$'*x)))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.3 * sin(2*pi*'br$'*x))"
    selectObject: channel[4]
    Formula: "self * 0.25"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(4*pi*'br$'*x) * (0.5 - 0.5*sin(pi*'br$'*x)))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(4*pi*'br$'*x + pi) * (0.5 - 0.5*sin(pi*'br$'*x)))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 - 0.4 * cos(4*pi*'br$'*x) * (0.5 + 0.5*cos(pi*'br$'*x)))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 - 0.4 * cos(4*pi*'br$'*x + pi) * (0.5 + 0.5*cos(pi*'br$'*x)))"

elsif pattern = 12
    # GALAXY - Stellar motion
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(2*pi*'br$'*x * (1 + 0.3*sin(0.5*pi*'br$'*x))))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(2*pi*'br$'*x * (1 + 0.3*sin(0.5*pi*'br$'*x)) + pi/2))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.3 * sin(3*pi*'br$'*x))"
    selectObject: channel[4]
    Formula: "self * (0.3 + 0.1 * sin(0.5*pi*'br$'*x))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(2*pi*'br$'*x * (1 + 0.3*sin(0.5*pi*'br$'*x)) + pi))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.4 * cos(2*pi*'br$'*x * (1 + 0.3*sin(0.5*pi*'br$'*x)) + 3*pi/2))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.35 * cos(2*pi*'br$'*x * (1 - 0.2*sin(0.5*pi*'br$'*x))))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.35 * cos(2*pi*'br$'*x * (1 - 0.2*sin(0.5*pi*'br$'*x)) + pi))"

elsif pattern = 13
    # LIGHTNING - Electrical discharge
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.45 * (randomUniform(0,1) > 0.7) * sin(20*pi*'br$'*x))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.45 * (randomUniform(0,1) > 0.7) * cos(20*pi*'br$'*x))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.4 * (randomUniform(0,1) > 0.8))"
    selectObject: channel[4]
    Formula: "self * (0.2 + 0.3 * (randomUniform(0,1) > 0.9))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.45 * (randomUniform(0,1) > 0.7) * sin(20*pi*'br$'*x + pi/2))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.45 * (randomUniform(0,1) > 0.7) * cos(20*pi*'br$'*x + pi/2))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.45 * (randomUniform(0,1) > 0.7) * sin(20*pi*'br$'*x + pi))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.45 * (randomUniform(0,1) > 0.7) * cos(20*pi*'br$'*x + pi))"

elsif pattern = 14
    # HEARTBEAT - Pulse expansion
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.3 + 0.6 * exp(-10*((x mod (1/'br$')) * 'br$')^2))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.3 + 0.6 * exp(-10*((x mod (1/'br$')) * 'br$')^2))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.4 + 0.5 * exp(-8*((x mod (1/'br$')) * 'br$')^2))"
    selectObject: channel[4]
    Formula: "self * (0.3 + 0.4 * exp(-5*((x mod (1/'br$')) * 'br$')^2))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.3 + 0.5 * exp(-12*((x mod (1/'br$') - 0.1/'br$') * 'br$')^2))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.3 + 0.5 * exp(-12*((x mod (1/'br$') - 0.1/'br$') * 'br$')^2))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.3 + 0.4 * exp(-15*((x mod (1/'br$') - 0.2/'br$') * 'br$')^2))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.3 + 0.4 * exp(-15*((x mod (1/'br$') - 0.2/'br$') * 'br$')^2))"

else
    # BREATHING - Lung expansion (pattern 15)
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(pi*'br$'*x))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * sin(pi*'br$'*x))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.35 * sin(pi*'br$'*x))"
    selectObject: channel[4]
    Formula: "self * (0.3 + 0.2 * sin(pi*'br$'*x))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.3 * sin(pi*'br$'*x - pi/6))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.3 * sin(pi*'br$'*x - pi/6))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.2 * sin(pi*'br$'*x - pi/3))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.2 * sin(pi*'br$'*x - pi/3))"
endif

appendInfoLine: "Pattern applied: ", patternName$

# === Combine to 8-channel ===
if create_8ch_combined
    selectObject: channel[1], channel[2]
    Combine to stereo
    pair12 = selected("Sound")
    
    selectObject: channel[3], channel[4]
    Combine to stereo
    pair34 = selected("Sound")
    
    selectObject: channel[5], channel[6]
    Combine to stereo
    pair56 = selected("Sound")
    
    selectObject: channel[7], channel[8]
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
    result8ch = selected("Sound")
    Scale peak: 0.95
    Rename: originalName$ + "_8ch_" + patternName$
    
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678
endif

# === Create binaural mix ===
if create_binaural_mix
    # Left ear: FL + 0.7*C + 0.5*SL + 0.3*BL
    selectObject: channel[1]
    Copy: "binL"
    binL = selected("Sound")
    
    selectObject: channel[3]
    Copy: "tempC"
    tempC = selected("Sound")
    Formula: "self * 0.7"
    selectObject: binL
    Formula: "self + object[tempC]"
    removeObject: tempC
    
    selectObject: channel[5]
    Copy: "tempSL"
    tempSL = selected("Sound")
    Formula: "self * 0.5"
    selectObject: binL
    Formula: "self + object[tempSL]"
    removeObject: tempSL
    
    selectObject: channel[7]
    Copy: "tempBL"
    tempBL = selected("Sound")
    Formula: "self * 0.3"
    selectObject: binL
    Formula: "self + object[tempBL]"
    removeObject: tempBL
    
    # Right ear: FR + 0.7*C + 0.5*SR + 0.3*BR
    selectObject: channel[2]
    Copy: "binR"
    binR = selected("Sound")
    
    selectObject: channel[3]
    Copy: "tempC2"
    tempC2 = selected("Sound")
    Formula: "self * 0.7"
    selectObject: binR
    Formula: "self + object[tempC2]"
    removeObject: tempC2
    
    selectObject: channel[6]
    Copy: "tempSR"
    tempSR = selected("Sound")
    Formula: "self * 0.5"
    selectObject: binR
    Formula: "self + object[tempSR]"
    removeObject: tempSR
    
    selectObject: channel[8]
    Copy: "tempBR"
    tempBR = selected("Sound")
    Formula: "self * 0.3"
    selectObject: binR
    Formula: "self + object[tempBR]"
    removeObject: tempBR
    
    selectObject: binL, binR
    Combine to stereo
    binaural = selected("Sound")
    Scale peak: 0.95
    Rename: originalName$ + "_binaural_" + patternName$
    
    removeObject: binL, binR
endif

# === Cleanup ===
removeObject: monoID
for ch from 1 to 8
    removeObject: channel[ch]
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
    Text: 0.5, "centre", 0.5, "half", "BPM Surround: " + patternName$ + " (" + string$(numCycles) + " cycles) | " + originalName$
    
    # Speaker layout
    Select outer viewport: 0.5, 5.0, 0.8, 4.5
    Select inner viewport: 0.8, 4.7, 1.1, 4.2
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Speaker positions (7.1 layout)
    # FL, FR, C, LFE, SL, SR, BL, BR
    spkX[1] = -0.8
    spkY[1] = 0.9
    spkX[2] = 0.8
    spkY[2] = 0.9
    spkX[3] = 0
    spkY[3] = 1.1
    spkX[4] = 0
    spkY[4] = -0.3
    spkX[5] = -1.1
    spkY[5] = 0
    spkX[6] = 1.1
    spkY[6] = 0
    spkX[7] = -0.8
    spkY[7] = -0.9
    spkX[8] = 0.8
    spkY[8] = -0.9
    
    # Draw speakers
    for ch from 1 to 8
        if ch = 4
            # LFE = different color
            Paint circle (mm): "{0.6, 0.4, 0.6}", spkX[ch], spkY[ch], 4
        else
            Paint circle (mm): "{0.3, 0.5, 0.7}", spkX[ch], spkY[ch], 4
        endif
        Colour: "White"
        Font size: 6
        Text: spkX[ch], "centre", spkY[ch], "half", chLabel$[ch]
    endfor
    
    # Listener
    Paint circle (mm): "{0.2, 0.6, 0.3}", 0, 0, 5
    Colour: "White"
    Font size: 6
    Text: 0, "centre", 0, "half", "L"
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "7.1 Speaker Layout"
    
    # Pattern info
    Select outer viewport: 5.2, 9.5, 0.8, 2.5
    Select inner viewport: 5.4, 9.3, 1.0, 2.3
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.85, "half", "Pattern: " + patternName$
    Text: 0.5, "centre", 0.65, "half", "Cycles: " + string$(numCycles)
    Text: 0.5, "centre", 0.45, "half", "Rate: " + fixed$(baseRate, 2) + " Hz"
    Text: 0.5, "centre", 0.25, "half", "Duration: " + fixed$(duration, 2) + "s"
    
    Draw inner box
    
    # Output waveform
    Select outer viewport: 5.2, 9.5, 2.7, 4.5
    Select inner viewport: 5.4, 9.3, 2.9, 4.3
    if create_8ch_combined
        selectObject: result8ch
    elsif create_binaural_mix
        selectObject: binaural
    endif
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
if create_8ch_combined
    appendInfoLine: "Created: 8-channel surround output"
endif
if create_binaural_mix
    appendInfoLine: "Created: Binaural headphone mix"
endif

if play_result
    if create_binaural_mix
        selectObject: binaural
        Play
    elsif create_8ch_combined
        selectObject: result8ch
        Play
    endif
endif

if create_8ch_combined
    selectObject: result8ch
elsif create_binaural_mix
    selectObject: binaural
endif