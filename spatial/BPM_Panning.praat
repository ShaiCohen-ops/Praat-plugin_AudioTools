# ============================================================
# Praat AudioTools - BPM_Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# EXPERIMENTAL CREATIVE PANNING EFFECTS
form Creative Panning Laboratory
    choice Cycles_Per_File: 4
        option 1 cycle (very slow)
        option 2 cycles
        option 4 cycles  
        option 8 cycles (medium)
        option 16 cycles
        option 32 cycles (fast)
        option 64 cycles (very fast)
    choice Panning_Pattern: 1
        option Spiral (accelerating)
        option Wobble (drunk walking)
        option Heartbeat (organic pulse)
        option Pendulum (physics swing)
        option Glitch (random jumps)
        option Doppler (racing car)
        option Breathing (inhale/exhale)
        option Lightning (chaotic strikes)
        option Orbit (elliptical motion)
        option Tsunami (building wave)
        option Fractal (multi-scale)
        option Neural (brain waves)
        option Quantum (probability)
        option Virus (spreading chaos)
        option DNA (double helix)
endform

# Select sound object
sound = selected("Sound")
selectObject: sound

# Check channels
num_channels = Get number of channels
if num_channels != 2
    exitScript: "Need stereo sound"
endif

# Get duration and calculate base rate
duration = Get total duration
appendInfoLine: "File duration: ", fixed$(duration, 2), " seconds"

# Calculate base rate
if cycles_Per_File = 1
    cycles = 1
elsif cycles_Per_File = 2
    cycles = 2
elsif cycles_Per_File = 3
    cycles = 4
elsif cycles_Per_File = 4
    cycles = 8
elsif cycles_Per_File = 5
    cycles = 16
elsif cycles_Per_File = 6
    cycles = 32
else
    cycles = 64
endif

base_rate = cycles / duration
appendInfoLine: "Base cycles: ", cycles
appendInfoLine: "Base rate: ", fixed$(base_rate, 2), " Hz"

# Create copy
selectObject: sound
Copy: "creative_panned"

# Apply CREATIVE panning effects
selectObject: "Sound creative_panned"

if panning_Pattern = 1
    # SPIRAL - Accelerating circular motion
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.4 * sin(2*pi*" + string$(base_rate) + "*x*x/" + string$(duration) + "))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.4 * sin(2*pi*" + string$(base_rate) + "*x*x/" + string$(duration) + "))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "SPIRAL - Accelerating motion"

elsif panning_Pattern = 2
    # WOBBLE - Drunk walking with random-ish movement
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.35 * sin(2*pi*" + string$(base_rate) + "*x) - 0.15 * sin(7*pi*" + string$(base_rate) + "*x))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.35 * sin(2*pi*" + string$(base_rate) + "*x) + 0.15 * sin(7*pi*" + string$(base_rate) + "*x))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "WOBBLE - Drunk walking"

elsif panning_Pattern = 3
    # HEARTBEAT - Organic double-thump pattern
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.4 * (sin(4*pi*" + string$(base_rate) + "*x) * exp(-20*((2*" + string$(base_rate) + "*x) mod 1 - 0.5)^2)))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.4 * (sin(4*pi*" + string$(base_rate) + "*x) * exp(-20*((2*" + string$(base_rate) + "*x) mod 1 - 0.5)^2)))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "HEARTBEAT - Organic pulse"

elsif panning_Pattern = 4
    # PENDULUM - Physics-based swing with gravity
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.45 * sin(2*pi*" + string$(base_rate) + "*x) * exp(-0.1*" + string$(base_rate) + "*x))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.45 * sin(2*pi*" + string$(base_rate) + "*x) * exp(-0.1*" + string$(base_rate) + "*x))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "PENDULUM - Decaying swing"

elsif panning_Pattern = 5
    # GLITCH - Random-ish jumps using pseudo-random (clamped to 0-1 range)
    Extract one channel: 1
    glitch_val$ = "sin(23*pi*" + string$(base_rate) + "*x) * sin(7*pi*" + string$(base_rate) + "*x)"
    left_formula$ = "self * max(0.05, min(0.95, 0.5 - 0.4 * (" + glitch_val$ + ")))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * max(0.05, min(0.95, 0.5 + 0.4 * (" + glitch_val$ + ")))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "GLITCH - Chaotic jumps (safe range)"

elsif panning_Pattern = 6
    # DOPPLER - Racing car effect with speed changes
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.4 * sin(2*pi*" + string$(base_rate) + "*x + 10*sin(0.5*pi*" + string$(base_rate) + "*x)))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.4 * sin(2*pi*" + string$(base_rate) + "*x + 10*sin(0.5*pi*" + string$(base_rate) + "*x)))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "DOPPLER - Racing car"

elsif panning_Pattern = 7
    # BREATHING - Inhale/exhale with natural rhythm
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.3 * (sin(pi*" + string$(base_rate) + "*x))^3)"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.3 * (sin(pi*" + string$(base_rate) + "*x))^3)"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "BREATHING - Inhale/exhale"

elsif panning_Pattern = 8
    # LIGHTNING - Chaotic strikes with multiple frequencies
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.3 * sin(2*pi*" + string$(base_rate) + "*x) - 0.2 * sin(13*pi*" + string$(base_rate) + "*x) - 0.1 * sin(29*pi*" + string$(base_rate) + "*x))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.3 * sin(2*pi*" + string$(base_rate) + "*x) + 0.2 * sin(13*pi*" + string$(base_rate) + "*x) + 0.1 * sin(29*pi*" + string$(base_rate) + "*x))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "LIGHTNING - Chaotic strikes"

elsif panning_Pattern = 9
    # ORBIT - Elliptical motion (non-circular)
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.4 * sin(2*pi*" + string$(base_rate) + "*x) - 0.2 * sin(4*pi*" + string$(base_rate) + "*x))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.4 * sin(2*pi*" + string$(base_rate) + "*x) + 0.2 * sin(4*pi*" + string$(base_rate) + "*x))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "ORBIT - Elliptical motion"

else
    # TSUNAMI - Building wave that grows stronger
    Extract one channel: 1
    left_formula$ = "self * (0.5 - 0.4 * sin(2*pi*" + string$(base_rate) + "*x) * (x/" + string$(duration) + "))"
    Formula: left_formula$
    Rename: "left_panned"
    
    selectObject: "Sound creative_panned"
    Extract one channel: 2
    right_formula$ = "self * (0.5 + 0.4 * sin(2*pi*" + string$(base_rate) + "*x) * (x/" + string$(duration) + "))"
    Formula: right_formula$
    Rename: "right_panned"
    pattern_name$ = "TSUNAMI - Building wave"
endif

# Handle the new extreme patterns (11-15)
if panning_Pattern >= 11
    # Remove the previous result and start over for extreme patterns
    removeObject: "Sound left_panned"
    removeObject: "Sound right_panned"
    
    selectObject: "Sound creative_panned"
    
    if panning_Pattern = 11
        # FRACTAL - Self-similar panning at multiple scales
        Extract one channel: 1
        fractal_val$ = "sin(2*pi*" + string$(base_rate) + "*x) * sin(8*pi*" + string$(base_rate) + "*x) * sin(32*pi*" + string$(base_rate) + "*x)"
        left_formula$ = "self * max(0.1, min(0.9, 0.5 - 0.3 * (" + fractal_val$ + ")))"
        Formula: left_formula$
        Rename: "left_panned"
        
        selectObject: "Sound creative_panned"
        Extract one channel: 2
        right_formula$ = "self * max(0.1, min(0.9, 0.5 + 0.3 * (" + fractal_val$ + ")))"
        Formula: right_formula$
        Rename: "right_panned"
        pattern_name$ = "FRACTAL - Multi-scale chaos"

    elsif panning_Pattern = 12
        # NEURAL - Brain-like activity (using approximation of tanh)
        Extract one channel: 1
        neural_input$ = "3*sin(2*pi*" + string$(base_rate) + "*x + 2*sin(5*pi*" + string$(base_rate) + "*x))"
        # Approximate tanh using rational function: tanh(x) ≈ x/(1+|x|) for smoother limiting
        neural_val$ = "(" + neural_input$ + ")/(1 + abs(" + neural_input$ + "))"
        left_formula$ = "self * max(0.05, min(0.95, 0.5 - 0.4 * (" + neural_val$ + ")))"
        Formula: left_formula$
        Rename: "left_panned"
        
        selectObject: "Sound creative_panned"
        Extract one channel: 2
        right_formula$ = "self * max(0.05, min(0.95, 0.5 + 0.4 * (" + neural_val$ + ")))"
        Formula: right_formula$
        Rename: "right_panned"
        pattern_name$ = "NEURAL - Brain wave activity"

    elsif panning_Pattern = 13
        # QUANTUM - Probability-based panning with wave interference
        Extract one channel: 1
        quantum_val$ = "(sin(2*pi*" + string$(base_rate) + "*x))^3 * (cos(3*pi*" + string$(base_rate) + "*x))^2"
        left_formula$ = "self * max(0.05, min(0.95, 0.5 - 0.4 * (" + quantum_val$ + ")))"
        Formula: left_formula$
        Rename: "left_panned"
        
        selectObject: "Sound creative_panned"
        Extract one channel: 2
        right_formula$ = "self * max(0.05, min(0.95, 0.5 + 0.4 * (" + quantum_val$ + ")))"
        Formula: right_formula$
        Rename: "right_panned"
        pattern_name$ = "QUANTUM - Probability waves"

    elsif panning_Pattern = 14
        # VIRUS - Spreading chaos with exponential growth and decay
        Extract one channel: 1
        virus_growth$ = "exp(-((2*" + string$(base_rate) + "*x) mod 4 - 2)^2)"
        virus_chaos$ = "sin(11*pi*" + string$(base_rate) + "*x) * sin(17*pi*" + string$(base_rate) + "*x)"
        virus_val$ = "(" + virus_chaos$ + ") * (" + virus_growth$ + ")"
        left_formula$ = "self * max(0.05, min(0.95, 0.5 - 0.35 * (" + virus_val$ + ")))"
        Formula: left_formula$
        Rename: "left_panned"
        
        selectObject: "Sound creative_panned"
        Extract one channel: 2
        right_formula$ = "self * max(0.05, min(0.95, 0.5 + 0.35 * (" + virus_val$ + ")))"
        Formula: right_formula$
        Rename: "right_panned"
        pattern_name$ = "VIRUS - Spreading chaos"

    else
        # DNA - Double helix with intertwined patterns
        Extract one channel: 1
        dna_helix1$ = "sin(2*pi*" + string$(base_rate) + "*x)"
        dna_helix2$ = "sin(2*pi*" + string$(base_rate) + "*x + pi/2)"
        dna_twist$ = "sin(0.5*pi*" + string$(base_rate) + "*x)"
        dna_val$ = "(" + dna_helix1$ + ") * (0.7 + 0.3 * (" + dna_twist$ + ")) + 0.2 * (" + dna_helix2$ + ")"
        left_formula$ = "self * max(0.1, min(0.9, 0.5 - 0.3 * (" + dna_val$ + ")))"
        Formula: left_formula$
        Rename: "left_panned"
        
        selectObject: "Sound creative_panned"
        Extract one channel: 2
        right_formula$ = "self * max(0.1, min(0.9, 0.5 + 0.3 * (" + dna_val$ + ")))"
        Formula: right_formula$
        Rename: "right_panned"
        pattern_name$ = "DNA - Double helix structure"
    endif
endif

# Combine channels
selectObject: "Sound left_panned"
plusObject: "Sound right_panned"
Combine to stereo
Rename: "creative_result"

# Clean up
removeObject: "Sound creative_panned"
removeObject: "Sound left_panned"
removeObject: "Sound right_panned"

# Play result
selectObject: "Sound creative_result"
appendInfoLine: "CREATIVE EFFECT: ", pattern_name$
appendInfoLine: "🎵 EXPERIMENTAL PANNING APPLIED! 🎵"
Play