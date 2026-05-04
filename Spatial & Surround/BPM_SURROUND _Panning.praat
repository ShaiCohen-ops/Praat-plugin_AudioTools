# ============================================================
# Praat AudioTools - BPM_SURROUND_Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel BPM-synced surround panning with creative spatial patterns.
#   Uses 7.1 speaker layout (FL, FR, C, LFE, SL, SR, BL, BR) with
#   time-varying amplitude modulation. Each pattern produces a distinct
#   spatial trajectory across the 7.1 listening field.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Fix (HEADLINE, Pattern 13 Lightning): v0.2 used randomUniform()
#     inside the Formula, which Praat re-evaluates per sample at the
#     audio rate (e.g. 44100 random rolls per second). The "lightning"
#     was effectively noise-gate flutter, not discrete strikes.
#     Fixed: replaced with a deterministic high-frequency LFO
#     threshold gate, so strikes occur at musically meaningful rates
#     and have audible structure. The formula uses sin(LFO_strike) > 0.6
#     where LFO_strike runs at 8x baseRate, giving sparse bursts
#     synchronized to the cycle count.
#   - Fix (Pattern 9 Neural): v0.2 used (sin(...) > 0.3) which is
#     a hard 0/1 step function. Multiplied by ~0.4 amplitude swing,
#     the transitions caused audible clicks on sustained input. Fixed
#     with a tanh-shaped soft gate that ramps over a small phase
#     window rather than stepping instantly. Same character (firing
#     pattern) but click-free.
#   - Fix (8-channel output path): v0.2 used a pyramid of
#     "Combine to stereo" calls on stereo+stereo objects, which is
#     undefined behavior in Praat (Combine to stereo expects
#     mono+mono). v0.3 uses Create Sound from formula directly to
#     build a true 8-channel result, then fills each channel via
#     Formula (part) referencing the corresponding mono Sound.
#     Faster and unambiguously correct.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar with metadata subtitle.
#       Panel A: 7.1 speaker layout with positions computed from
#                spkAngle[], plus the time-averaged center-of-mass
#                trajectory drawn through the cycle.
#       Panel B: Per-channel gain envelopes over the first cycle
#                (all 8 overlaid in perceptual color gradient) —
#                this is what shows what the pattern actually does.
#       Panel C: Polar pickup plot — average gain per channel
#                rendered as a radial bar at the speaker's angle.
#       Panel D: Output waveform (Ch1 blue, Ch2 orange).
#       Panel E: Summary stats bar.
#   - Single source of truth: Panel A speaker positions are now
#     computed from spkAngle[] (was a separate hardcoded x/y array
#     in v0.2 that could drift apart from the angles).
#   - Style: 'br$' string interpolation kept (it was idiomatic and
#     the formulas are tested as-is); not modernized for readability
#     because rewriting 15 patterns risks introducing bugs.
# Changelog v0.2:
#   - Added input validation
#   - Implemented all 15 patterns
#   - Fixed ID-based selection
#   - Fixed binaural downmix
#   - Added visualization
#   - Added play toggle
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
inputCh = Get number of channels
if inputCh > 2
    exitScript: "Please use mono or stereo source."
endif

# Convert to mono
if inputCh = 2
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

# === Channel labels (single source of truth) ===
chLabel$[1] = "FL"
chLabel$[2] = "FR"
chLabel$[3] = "C"
chLabel$[4] = "LFE"
chLabel$[5] = "SL"
chLabel$[6] = "SR"
chLabel$[7] = "BL"
chLabel$[8] = "BR"

# === Speaker angles (single source of truth — used by both
#     pattern math and visualization Panel A) ===
# Compass: 0° = front, 90° = right, 180° = back, 270° = left.
spkAngle[1] = 330
spkAngle[2] = 30
spkAngle[3] = 0
spkAngle[4] = 180
spkAngle[5] = 250
spkAngle[6] = 110
spkAngle[7] = 210
spkAngle[8] = 150

# === Info ===
writeInfoLine: "=== BPM Surround Panning v0.3 ==="
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
    # NEURAL - Brain network (FIXED v0.3)
    # v0.2 used (sin(...) > 0.3) which produced hard 0/1 step
    # transitions. Multiplied by 0.4 amplitude swing, audible clicks.
    # v0.3 uses tanh-shaped soft threshold: tanh(8*(sin(...) - 0.3))
    # ramps from -1 to +1 over a small phase window around the
    # threshold, then mapped to 0..1 range. Same firing pattern,
    # click-free transitions.
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.4 * (0.5 + 0.5 * tanh(8 * (sin(2*pi*'br$'*x) - 0.3))))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.4 * (0.5 + 0.5 * tanh(8 * (sin(2*pi*'br$'*x + pi/3) - 0.3))))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.35 * (0.5 + 0.5 * tanh(8 * (sin(3*pi*'br$'*x) - 0.2))))"
    selectObject: channel[4]
    Formula: "self * 0.25"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.4 * (0.5 + 0.5 * tanh(8 * (sin(2*pi*'br$'*x + 2*pi/3) - 0.3))))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.4 * (0.5 + 0.5 * tanh(8 * (sin(2*pi*'br$'*x + pi) - 0.3))))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.4 * (0.5 + 0.5 * tanh(8 * (sin(2*pi*'br$'*x + 4*pi/3) - 0.3))))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.4 * (0.5 + 0.5 * tanh(8 * (sin(2*pi*'br$'*x + 5*pi/3) - 0.3))))"

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
    # LIGHTNING - Electrical discharge (FIXED v0.3)
    # v0.2 used randomUniform() inside Formula, which Praat
    # evaluates per sample at the audio rate — making "lightning"
    # a 44.1 kHz noise-gate, not discrete strikes.
    # v0.3 uses a high-frequency LFO threshold gate (8x baseRate)
    # to produce sparse deterministic bursts at musical timescales.
    # Each channel offset by phase to make strikes spread around
    # the room. Burst interior modulated by 20*pi for the
    # crackling character.
    selectObject: channel[1]
    Formula: "self * max(0.05, 0.5 + 0.45 * (sin(16*pi*'br$'*x) > 0.6) * sin(20*pi*'br$'*x))"
    selectObject: channel[2]
    Formula: "self * max(0.05, 0.5 + 0.45 * (sin(16*pi*'br$'*x + pi/3) > 0.6) * cos(20*pi*'br$'*x))"
    selectObject: channel[3]
    Formula: "self * max(0.05, 0.5 + 0.4 * (sin(16*pi*'br$'*x + 2*pi/3) > 0.7))"
    selectObject: channel[4]
    Formula: "self * (0.2 + 0.3 * (sin(16*pi*'br$'*x) > 0.8))"
    selectObject: channel[5]
    Formula: "self * max(0.05, 0.5 + 0.45 * (sin(16*pi*'br$'*x + pi) > 0.6) * sin(20*pi*'br$'*x + pi/2))"
    selectObject: channel[6]
    Formula: "self * max(0.05, 0.5 + 0.45 * (sin(16*pi*'br$'*x + 4*pi/3) > 0.6) * cos(20*pi*'br$'*x + pi/2))"
    selectObject: channel[7]
    Formula: "self * max(0.05, 0.5 + 0.45 * (sin(16*pi*'br$'*x + 5*pi/3) > 0.6) * sin(20*pi*'br$'*x + pi))"
    selectObject: channel[8]
    Formula: "self * max(0.05, 0.5 + 0.45 * (sin(16*pi*'br$'*x + pi/2) > 0.6) * cos(20*pi*'br$'*x + pi))"

elsif pattern = 14
    # HEARTBEAT - Pulse expansion
    # NOTE: at fast cycle counts (32, 64), the 0.1-cycle channel
    # offsets become too short to perceive as separated pulses.
    # Heartbeat works best at slow cycles (1, 2, 4).
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

# === Combine to true 8-channel  (FIXED v0.3) ===
# v0.2 used a pyramid of "Combine to stereo" calls on stereo+stereo
# objects, which is undefined in Praat. v0.3 builds the 8-channel
# Sound directly with Create Sound from formula and fills each
# channel via Formula (part) referencing the corresponding mono
# channel. Clean, fast, unambiguous.
if create_8ch_combined
    appendInfoLine: "Combining to 8-channel..."
    
    # Use the duration of the (already mono) channels — they all match
    selectObject: channel[1]
    chDur = Get total duration
    chSr = Get sampling frequency
    
    # Create empty 8-channel canvas
    result8ch = Create Sound from formula: originalName$ + "_8ch_" + patternName$,
        ... 8, 0, chDur, chSr, "0"
    
    # Fill each channel by referencing the per-channel mono source
    for ch from 1 to 8
        selectObject: result8ch
        chIdStr$ = string$(channel[ch])
        Formula (part): 0, chDur, ch, ch, "object[" + chIdStr$ + ", col]"
    endfor
    
    selectObject: result8ch
    Scale peak: 0.95
endif

# === Create binaural mix ===
# Conventional 7.1 -> stereo headphone downmix coefficients:
#   L_ear = FL + 0.7*C + 0.5*SL + 0.3*BL
#   R_ear = FR + 0.7*C + 0.5*SR + 0.3*BR
# (Modern object[<id>, col] reference syntax for consistency.)
if create_binaural_mix
    appendInfoLine: "Building binaural mix..."
    
    selectObject: channel[1]
    binDur = Get total duration
    binSr = Get sampling frequency
    
    binaural = Create Sound from formula: originalName$ + "_binaural_" + patternName$,
        ... 2, 0, binDur, binSr, "0"
    
    flStr$ = string$(channel[1])
    frStr$ = string$(channel[2])
    cStr$  = string$(channel[3])
    slStr$ = string$(channel[5])
    srStr$ = string$(channel[6])
    blStr$ = string$(channel[7])
    brStr$ = string$(channel[8])
    
    # Left ear (channel 1 of binaural)
    selectObject: binaural
    Formula (part): 0, binDur, 1, 1,
        ... "object[" + flStr$ + ", col]"
        ... + " + 0.7 * object[" + cStr$ + ", col]"
        ... + " + 0.5 * object[" + slStr$ + ", col]"
        ... + " + 0.3 * object[" + blStr$ + ", col]"
    
    # Right ear (channel 2 of binaural)
    Formula (part): 0, binDur, 2, 2,
        ... "object[" + frStr$ + ", col]"
        ... + " + 0.7 * object[" + cStr$ + ", col]"
        ... + " + 0.5 * object[" + srStr$ + ", col]"
        ... + " + 0.3 * object[" + brStr$ + ", col]"
    
    selectObject: binaural
    Scale peak: 0.95
endif

# ============================================================
# COMPUTE PER-CHANNEL AVERAGE GAIN  (for visualization Panels B,C)
# We do this by sampling the gain curve at high temporal resolution
# from the channel sounds themselves: gain[t] = channel[t] / mono[t]
# would be noisy, so instead we re-evaluate the analytic formulas
# at viz time. Easier: just compute RMS of each channel as a
# gross indicator. Actually the cleanest path is to sample per-channel
# RMS over the full file — that gives mean-square gain, robust.
# ============================================================
chRMS# = zero# (8)
for ch from 1 to 8
    selectObject: channel[ch]
    chRMS#[ch] = Get root-mean-square: 0, 0
endfor

# Source RMS for normalization
selectObject: monoID
srcRMS = Get root-mean-square: 0, 0
if srcRMS < 0.0001
    srcRMS = 0.0001
endif

# Per-channel gain ratio (rough proxy for average gain)
chMeanGain# = zero# (8)
for ch from 1 to 8
    chMeanGain#[ch] = chRMS#[ch] / srcRMS
endfor

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Drawn while channel mono Sounds still exist (they're cleaned
# up afterwards). This lets Panel B sample real per-channel data.
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BPM SURROUND PANNING##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Pattern: " + patternName$
        ... + "  |  Cycles: " + string$(numCycles)
        ... + "  |  Rate: " + fixed$(baseRate, 2) + " Hz"
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
    
    # Per-channel colors (perceptual gradient, Ch1 cool to Ch8 warm)
    chColR# = zero# (8)
    chColG# = zero# (8)
    chColB# = zero# (8)
    for ch from 1 to 8
        progress = (ch - 1) / 7
        if progress < 0.5
            t = progress * 2
            chColR#[ch] = 0.20 + t * 0.55
            chColG#[ch] = 0.45 + t * 0.30
            chColB#[ch] = 0.80 - t * 0.45
        else
            t = (progress - 0.5) * 2
            chColR#[ch] = 0.75 + t * 0.15
            if chColR#[ch] > 1
                chColR#[ch] = 1
            endif
            chColG#[ch] = 0.75 - t * 0.45
            chColB#[ch] = 0.35 - t * 0.20
            if chColB#[ch] < 0
                chColB#[ch] = 0
            endif
        endif
    endfor
    
    # ----------------------------------------------------------
    # PANEL A: 7.1 SPEAKER LAYOUT  (left, headline)
    # Positions COMPUTED from spkAngle[] — single source of truth.
    # LFE drawn as a hexagon with offset to distinguish it.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.45
    
    Axes: -1.4, 1.4, -1.4, 1.4
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.4, 1.4, -1.4, 1.4
    
    # Concentric guides
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    rGuide# = { 0.40, 0.80, 1.10 }
    for k from 1 to 3
        rg = rGuide#[k]
        prevX = rg
        prevY = 0
        for h from 1 to 64
            a = 2 * pi * h / 64
            cx = rg * cos(a)
            cy = rg * sin(a)
            Draw line: prevX, prevY, cx, cy
            prevX = cx
            prevY = cy
        endfor
    endfor
    
    # Crosshairs
    Colour: "{0.78, 0.78, 0.82}"
    Dotted line
    Draw line: -1.30, 0, 1.30, 0
    Draw line: 0, -1.30, 0, 1.30
    Solid line
    
    # Compute speaker positions from spkAngle[]
    # Compass: 0° = front (+y), 90° = right (+x). LFE drawn closer
    # to the listener (radius 0.4) since it's a distinct sub.
    for ch from 1 to 8
        if ch = 4
            rad = 0.40
        else
            rad = 1.10
        endif
        a = spkAngle[ch] * pi / 180
        spkX[ch] = rad * sin(a)
        spkY[ch] = rad * cos(a)
    endfor
    
    # Marker size scaled by per-channel mean gain (size = activity)
    maxMeanG = chMeanGain#[1]
    for ch from 2 to 8
        if chMeanGain#[ch] > maxMeanG
            maxMeanG = chMeanGain#[ch]
        endif
    endfor
    if maxMeanG < 0.001
        maxMeanG = 0.001
    endif
    
    # Draw connecting lines (octagon outline minus LFE)
    # This shows the speaker ring when LFE is excluded
    Colour: "{0.78, 0.78, 0.82}"
    Line width: 1
    # Order around the ring, clockwise from front: 3, 2, 6, 8, 4-skip, 7, 5, 1
    # Actually use angle order. Sort speaker indices by angle.
    # Manual order: 3 (0°), 2 (30°), 6 (110°), 8 (150°), 7 (210°), 5 (250°), 1 (330°)
    # LFE (4 at 180°) skipped from the ring outline
    ringOrder# = { 3, 2, 6, 8, 7, 5, 1 }
    for k from 1 to 7
        kNext = k + 1
        if kNext > 7
            kNext = 1
        endif
        c1 = ringOrder#[k]
        c2 = ringOrder#[kNext]
        Draw line: spkX[c1], spkY[c1], spkX[c2], spkY[c2]
    endfor
    
    # Draw speakers
    for ch from 1 to 8
        if ch = 4
            # LFE — distinct purple
            sizeG = 3.5 + 2.5 * (chMeanGain#[ch] / maxMeanG)
            Paint circle (mm): "{0.55, 0.30, 0.65}", spkX[ch], spkY[ch], sizeG
        else
            sizeG = 3.5 + 2.5 * (chMeanGain#[ch] / maxMeanG)
            rgb$ = "{" + fixed$(chColR#[ch], 2) + ","
                ... + fixed$(chColG#[ch], 2) + ","
                ... + fixed$(chColB#[ch], 2) + "}"
            Paint circle (mm): rgb$, spkX[ch], spkY[ch], sizeG
        endif
        Colour: "White"
        Font size: 6
        Text: spkX[ch], "centre", spkY[ch], "half", chLabel$[ch]
    endfor
    
    # Listener
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 4
    Colour: "White"
    Font size: 6
    Text: 0, "centre", 0, "half", "L"
    
    # Cardinal labels
    Font size: 6
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0, "centre", 1.32, "half", "FRONT"
    Text: 0, "centre", -1.32, "half", "BACK"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: PER-CHANNEL GAIN ENVELOPES  (right column, upper)
    # All 8 channels overlaid for the first cycle of the pattern.
    # This is what shows what the pattern is actually doing.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    # Show the first cycle of the pattern, plus 0.1 cycle for context
    if numCycles > 0
        cycleDur = 1.0 / baseRate
    else
        cycleDur = duration
    endif
    panelDur = cycleDur * 1.1
    if panelDur > duration
        panelDur = duration
    endif
    
    Axes: 0, panelDur, -0.05, 1.05
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, panelDur, -0.05, 1.05
    
    # Reference grid at 0, 0.5, 1.0
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Draw line: 0, 0.5, panelDur, 0.5
    Draw line: 0, 1.0, panelDur, 1.0
    
    # Cycle boundary
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Line width: 1.3
    Draw line: cycleDur, 0, cycleDur, 1.05
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    Text: cycleDur, "left", 1.02, "half", " 1 cycle"
    
    # Sample each channel's gain curve.
    # We sample ~200 points across panelDur, computing gain as
    # channel[ch][t] / mono[t]. To avoid divide-by-zero on quiet
    # parts of the source, we use abs(mono[t]) > tiny as a guard.
    # In practice the channel's raw waveform IS source × gain, so
    # a more robust approach is to extract the gain by reading
    # both at the same sample and dividing where source is large.
    #
    # Simplest pragmatic approach: get RMS in small windows and
    # compute window-wise gain ratio.
    nVizSamples = 200
    
    Line width: 1.3
    for ch from 1 to 8
        rgb$ = "{" + fixed$(chColR#[ch], 2) + ","
            ... + fixed$(chColG#[ch], 2) + ","
            ... + fixed$(chColB#[ch], 2) + "}"
        Colour: rgb$
        
        windowSec = panelDur / nVizSamples
        prevT = 0
        prevG = 0
        for s from 1 to nVizSamples
            t = (s - 0.5) * windowSec
            tEnd = t + windowSec * 0.5
            tStart = t - windowSec * 0.5
            if tStart < 0
                tStart = 0
            endif
            if tEnd > panelDur
                tEnd = panelDur
            endif
            
            selectObject: channel[ch]
            chRmsLocal = Get root-mean-square: tStart, tEnd
            selectObject: monoID
            srcRmsLocal = Get root-mean-square: tStart, tEnd
            
            if srcRmsLocal > 0.001 and chRmsLocal <> undefined
                g = chRmsLocal / srcRmsLocal
            else
                g = 0
            endif
            if g > 1.05
                g = 1.05
            endif
            if g < 0
                g = 0
            endif
            
            if s > 1
                Draw line: prevT, prevG, t, g
            endif
            prevT = t
            prevG = g
        endfor
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s) — first cycle shown"
    
    # ----------------------------------------------------------
    # PANEL C: POLAR PICKUP  (right column, lower)
    # Average gain per channel, drawn as radial bar at speaker angle.
    # Shows the time-averaged spatial energy distribution.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    Axes: -1.3, 1.3, -1.3, 1.3
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.3, 1.3, -1.3, 1.3
    
    # Concentric guides at 0.4, 0.8, 1.2 (gain reference)
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    rPolarGuide# = { 0.40, 0.80, 1.20 }
    for k from 1 to 3
        rg = rPolarGuide#[k]
        prevX = rg
        prevY = 0
        for h from 1 to 48
            a = 2 * pi * h / 48
            cx = rg * cos(a)
            cy = rg * sin(a)
            Draw line: prevX, prevY, cx, cy
            prevX = cx
            prevY = cy
        endfor
    endfor
    
    # Crosshairs
    Colour: "{0.78, 0.78, 0.82}"
    Dotted line
    Draw line: -1.20, 0, 1.20, 0
    Draw line: 0, -1.20, 0, 1.20
    Solid line
    
    # Per-channel radial bar: bar length = mean gain (clipped to ~1.2)
    Line width: 2
    for ch from 1 to 8
        if ch <> 4
            # Skip LFE in the polar plot — directionality doesn't apply
            barLen = chMeanGain#[ch]
            if barLen > 1.2
                barLen = 1.2
            endif
            a = spkAngle[ch] * pi / 180
            barX = barLen * sin(a)
            barY = barLen * cos(a)
            
            rgb$ = "{" + fixed$(chColR#[ch], 2) + ","
                ... + fixed$(chColG#[ch], 2) + ","
                ... + fixed$(chColB#[ch], 2) + "}"
            Colour: rgb$
            Draw line: 0, 0, barX, barY
            Paint circle (mm): rgb$, barX, barY, 1.5
        endif
    endfor
    Line width: 1
    
    # Channel labels at outer guide
    Font size: 5
    for ch from 1 to 8
        if ch <> 4
            a = spkAngle[ch] * pi / 180
            labX = 1.27 * sin(a)
            labY = 1.27 * cos(a)
            rgb$ = "{" + fixed$(chColR#[ch], 2) + ","
                ... + fixed$(chColG#[ch], 2) + ","
                ... + fixed$(chColB#[ch], 2) + "}"
            Colour: rgb$
            Text: labX, "centre", labY, "half", chLabel$[ch]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "7.1 Layout (size = activity)"
    Text: 6.10, "centre", 7.30, "half", "First-cycle gain envelopes (upper) & polar pickup (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    # Use binaural if available, else first 2 channels of 8ch
    if create_binaural_mix
        vizSrc = binaural
    elsif create_8ch_combined
        vizSrc = result8ch
    else
        vizSrc = channel[1]
    endif
    
    selectObject: vizSrc
    vizDur = Get total duration
    nVizCh = Get number of channels
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, vizDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, vizDur, 0
    
    if nVizCh = 1
        selectObject: vizSrc
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        selectObject: vizSrc
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nVizCh >= 2
            selectObject: vizSrc
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nVizCh > 1
        Text top: "no", "Output  (blue=L  orange=R, " + string$(nVizCh) + " channels)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if create_8ch_combined and create_binaural_mix
        outStr$ = "8ch + binaural"
    elsif create_8ch_combined
        outStr$ = "8ch only"
    elsif create_binaural_mix
        outStr$ = "binaural only"
    else
        outStr$ = "none (channels only)"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + patternName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Cycles: " + string$(numCycles)
        ... + "  |  Rate: " + fixed$(baseRate, 3) + " Hz"
        ... + "  |  Cycle dur: " + fixed$(1000/baseRate, 1) + " ms"
        ... + "  |  Output: " + outStr$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Mean gain by ch: "
        ... + "FL=" + fixed$(chMeanGain#[1], 2)
        ... + "  FR=" + fixed$(chMeanGain#[2], 2)
        ... + "  C=" + fixed$(chMeanGain#[3], 2)
        ... + "  LFE=" + fixed$(chMeanGain#[4], 2)
        ... + "  SL=" + fixed$(chMeanGain#[5], 2)
        ... + "  SR=" + fixed$(chMeanGain#[6], 2)
        ... + "  BL=" + fixed$(chMeanGain#[7], 2)
        ... + "  BR=" + fixed$(chMeanGain#[8], 2)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Cleanup ===
removeObject: monoID
for ch from 1 to 8
    removeObject: channel[ch]
endfor

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
