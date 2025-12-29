# ============================================================
# Praat AudioTools - PolyrhythmsFromDots.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PolyrhythmsFromDots
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
form PolyrhythmsFromDots
    optionmenu Preset: 1
        option Custom
        option 3 vs 4 (Waltz)
        option 5 vs 7 (Complex)
        option 2 vs 3 (Simple)
        option 4 vs 5 (Jazz)
        option 3 vs 5 (African)
        option 7 vs 8 (Dense)
        option 4 vs 7 (Progressive)
        option 5 vs 9 (Math Rock)
    comment Line 1 (Top - Left Channel)
    integer dots1 5
    comment Line 2 (Bottom - Right Channel)
    integer dots2 7
    comment Timing (in seconds)
    real barDuration 2.0
    real dotDur 0.05
    comment Sound
    real baseFreq 220
    integer samplerate 22050
    real dotRadius 0.01
    real amplitude 0.5
    comment Panning
    real panAmount 0.8
endform

# Apply presets
if preset > 1
    if preset = 2
        # 3 vs 4 (Waltz)
        dots1 = 3
        dots2 = 4
        barDuration = 3.0
        baseFreq = 196
        
    elsif preset = 3
        # 5 vs 7 (Complex)
        dots1 = 5
        dots2 = 7
        barDuration = 3.5
        baseFreq = 220
        
    elsif preset = 4
        # 2 vs 3 (Simple)
        dots1 = 2
        dots2 = 3
        barDuration = 2.0
        baseFreq = 165
        
    elsif preset = 5
        # 4 vs 5 (Jazz)
        dots1 = 4
        dots2 = 5
        barDuration = 4.0
        baseFreq = 262
        
    elsif preset = 6
        # 3 vs 5 (African)
        dots1 = 3
        dots2 = 5
        barDuration = 2.5
        baseFreq = 147
        
    elsif preset = 7
        # 7 vs 8 (Dense)
        dots1 = 7
        dots2 = 8
        barDuration = 4.0
        baseFreq = 330
        dotDur = 0.03
        
    elsif preset = 8
        # 4 vs 7 (Progressive)
        dots1 = 4
        dots2 = 7
        barDuration = 3.0
        baseFreq = 196
        
    elsif preset = 9
        # 5 vs 9 (Math Rock)
        dots1 = 5
        dots2 = 9
        barDuration = 5.0
        baseFreq = 220
        dotDur = 0.04
    endif
endif

echo Using preset: 'preset'
echo Rhythm: 'dots1' vs 'dots2'

Erase all

# Calculate spacing to fit rhythms in one bar
spacing1 = barDuration / dots1
spacing2 = barDuration / dots2

# Create empty sounds for each channel
Create Sound from formula: "leftChannel", 1, 0, barDuration, samplerate, "0"
Create Sound from formula: "rightChannel", 1, 0, barDuration, samplerate, "0"

# Draw left channel dots and generate sound
select Sound leftChannel
for i from 1 to dots1
    x1 = (i - 1) * spacing1
    y1 = 0.8
    Draw circle: x1, y1, dotRadius
    
    startTime = x1
    endTime = x1 + dotDur
    
    # Calculate pan position
    panPos = -1 + (2 * (i - 1) / (dots1 - 1))
    panPos = panPos * panAmount
    
    # Calculate left and right amplitude based on pan
    leftAmp = amplitude * (1 - panPos) / 2
    rightAmp = amplitude * (1 + panPos) / 2
    
    # Add panned sine wave
    part1$ = "self + if x >= " + string$(startTime)
    part2$ = " and x < " + string$(endTime)
    part3$ = " then " + string$(leftAmp) + "*sin(2*pi*" + string$(baseFreq)
    part4$ = "*(x - " + string$(startTime) + ")) else 0 fi"
    formula_str$ = part1$ + part2$ + part3$ + part4$
    
    Formula: formula_str$
endfor

# Draw right channel dots and generate sound
select Sound rightChannel
for i from 1 to dots2
    x2 = (i - 1) * spacing2
    y2 = 0.2
    Draw circle: x2, y2, dotRadius
    
    startTime = x2
    endTime = x2 + dotDur
    freq_mult = baseFreq * 1.5
    
    # Calculate pan position for right channel
    panPos = -1 + (2 * (i - 1) / (dots2 - 1))
    panPos = panPos * panAmount
    
    # Calculate left and right amplitude based on pan
    leftAmp = amplitude * (1 - panPos) / 2
    rightAmp = amplitude * (1 + panPos) / 2
    
    # Add panned sine wave
    part1$ = "self + if x >= " + string$(startTime)
    part2$ = " and x < " + string$(endTime)
    part3$ = " then " + string$(rightAmp) + "*sin(2*pi*" + string$(freq_mult)
    part4$ = "*(x - " + string$(startTime) + ")) else 0 fi"
    formula_str$ = part1$ + part2$ + part3$ + part4$
    
    Formula: formula_str$
endfor

# Combine the two channels into stereo
select Sound leftChannel
plus Sound rightChannel
Combine to stereo
Rename: "polyrhythm_'dots1'_'dots2'_panned"

# Play the final stereo sound
Play

# Clean up all temporary objects
select all
Remove

echo Polyrhythm 'dots1' vs 'dots2' complete!