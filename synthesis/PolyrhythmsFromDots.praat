form PolyrhythmsFromDots
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
Rename: "polyrhythm_7_5_panned"

# Play the final stereo sound
Play

# Clean up all temporary objects
select all
Remove