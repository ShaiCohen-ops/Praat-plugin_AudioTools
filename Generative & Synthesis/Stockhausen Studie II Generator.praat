# ============================================================
# Praat AudioTools - Stockhausen Studie II Generator (10 seconds)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Studie II Generator (10 seconds)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Studie II Generator - Random & Authentic Modes
# ================================================

form Studie II Generator
    comment Generation mode:
    optionmenu generation_mode 1
        option Random (varied each time, quasi-Studie II)
        option Serial (authentic reconstruction, deterministic)
    comment Composition parameters:
    positive duration 10.0
    positive num_groups 7
    comment Audio settings:
    positive sample_rate 44100
    positive base_frequency 100
    comment Amplitude range (0.0 - 1.0):
    positive min_amplitude 0.10
    positive max_amplitude 0.30
    comment Options:
    boolean draw_score 1
    boolean save_to_file 0
    comment For Serial mode - starting position (0 = beginning):
    integer rotation_offset 0
    comment For Random mode - seed (0 = different each time):
    integer random_seed 0
endform

# Set variables from form
duration = duration
sampleRate = sample_rate
baseHz = base_frequency
minAmp = min_amplitude
maxAmp = max_amplitude
numGroupsTarget = num_groups
doDrawScore = draw_score
doSaveFile = save_to_file
genMode = generation_mode
rotationOffset = rotation_offset
seedValue = random_seed

# Basic time unit (for serial mode)
baseTimeUnit = 0.0328

# Build frequency scale (81 frequencies)
for i from 1 to 81
    freq_'i' = baseHz * (5 ^ ((i - 1) / 25))
endfor

# ========================================================
# SERIAL MODE SETUP (only if needed)
# ========================================================

if genMode == 2
    # Primary seed row (the documented input series)
    seed_1 = 3
    seed_2 = 5
    seed_3 = 1
    seed_4 = 4
    seed_5 = 2
    
    # Generate 5×5 number-square (Latin square technique)
    for colIdx from 1 to 5
        square_1_'colIdx' = seed_'colIdx'
    endfor
    
    for colIdx from 1 to 5
        srcCol = ((colIdx - 1 + 1) mod 5) + 1
        square_2_'colIdx' = seed_'srcCol'
    endfor
    
    for colIdx from 1 to 5
        srcCol = ((colIdx - 1 + 2) mod 5) + 1
        square_3_'colIdx' = seed_'srcCol'
    endfor
    
    for colIdx from 1 to 5
        srcCol = ((colIdx - 1 + 3) mod 5) + 1
        square_4_'colIdx' = seed_'srcCol'
    endfor
    
    for colIdx from 1 to 5
        srcCol = ((colIdx - 1 + 4) mod 5) + 1
        square_5_'colIdx' = seed_'srcCol'
    endfor
    
    # Duration multipliers
    durMult_1 = 1
    durMult_2 = 2
    durMult_3 = 4
    durMult_4 = 8
    durMult_5 = 16
    
    # Initialize token stream position
    tokenRow = 1 + (abs(rotationOffset) mod 5)
    tokenCol = 1
    
    # Section structure
    sectionType_1 = 1
    sectionType_2 = 2
    sectionType_3 = 3
    sectionType_4 = 1
    sectionType_5 = 2
endif

# ========================================================
# Create master timeline
# ========================================================

Create Sound from formula: "master", 1, 0, duration, sampleRate, "0"
master = selected("Sound")

# Event storage for score drawing
numStoredEvents = 0

# ========================================================
# MAIN GENERATION - Branch by mode
# ========================================================

if genMode == 1
    # ========================================================
    # RANDOM MODE
    # ========================================================
    
    currentTime = 0
    numGroups = numGroupsTarget
    
    for iGroup from 1 to numGroups
        if currentTime >= duration - 0.05
            goto DONE_GENERATION
        endif
        
        groupType = randomInteger(0, 1)
        numEvents = randomInteger(1, 5)
        
        if groupType == 0
            # Horizontal: sequential
            for iEv from 1 to numEvents
                if currentTime >= duration - 0.05
                    goto DONE_GENERATION
                endif
                
                spreadFactor = randomInteger(1, 5)
                startIdx = randomInteger(10, 65 - 4 * spreadFactor)
                evDur = randomUniform(0.08, 0.45)
                
                if currentTime + evDur > duration
                    evDur = duration - currentTime
                endif
                
                evAmp = randomUniform(minAmp, maxAmp)
                envType = randomInteger(1, 6)
                
                call generateMixtureRandom currentTime startIdx spreadFactor evDur evAmp envType
                
                currentTime = currentTime + evDur + randomUniform(0.005, 0.06)
            endfor
            
            if randomUniform(0, 1) > 0.4
                currentTime = currentTime + randomUniform(0.03, 0.25)
            endif
        else
            # Vertical: overlapping
            groupStart = currentTime
            groupLen = randomUniform(0.25, 0.7)
            
            for iEv from 1 to numEvents
                if groupStart >= duration - 0.05
                    goto SKIP_VERTICAL
                endif
                
                spreadFactor = randomInteger(1, 5)
                startIdx = randomInteger(10, 65 - 4 * spreadFactor)
                evDur = randomUniform(groupLen * 0.6, groupLen * 1.3)
                evStart = groupStart + randomUniform(0, groupLen * 0.25)
                
                if evStart + evDur > duration
                    evDur = duration - evStart
                endif
                
                if evDur < 0.03
                    goto SKIP_VERTICAL_EVENT
                endif
                
                evAmp = randomUniform(minAmp, maxAmp)
                envType = randomInteger(1, 6)
                
                call generateMixtureRandom evStart startIdx spreadFactor evDur evAmp envType
                
                label SKIP_VERTICAL_EVENT
            endfor
            
            label SKIP_VERTICAL
            currentTime = groupStart + groupLen + randomUniform(0.01, 0.12)
        endif
    endfor

else
    # ========================================================
    # SERIAL MODE (Authentic)
    # ========================================================
    
    currentTime = 0
    sectionNum = 1
    
    while currentTime < duration and sectionNum <= 5
        secType = sectionType_'sectionNum'
        
        for subsectionNum from 1 to 5
            if currentTime >= duration
                goto DONE_GENERATION
            endif
            
            call getNextToken
            numMixtures = nextTokenValue
            
            if secType == 1
                # Horizontal linked
                for iMix from 1 to numMixtures
                    if currentTime >= duration
                        goto DONE_GENERATION
                    endif
                    
                    call generateMixtureSerial currentTime
                    currentTime = currentTime + mixtureDuration
                endfor
                
            elsif secType == 2
                # Horizontal separated
                for iMix from 1 to numMixtures
                    if currentTime >= duration
                        goto DONE_GENERATION
                    endif
                    
                    call generateMixtureSerial currentTime
                    currentTime = currentTime + mixtureDuration
                    
                    call getNextToken
                    gapUnits = nextTokenValue
                    currentTime = currentTime + gapUnits * baseTimeUnit * 0.5
                endfor
                
            else
                # Vertical
                groupStartTime = currentTime
                maxDuration = 0
                
                for iMix from 1 to numMixtures
                    if currentTime >= duration
                        goto DONE_GENERATION
                    endif
                    
                    call getNextToken
                    staggerUnits = nextTokenValue
                    mixStartTime = groupStartTime + staggerUnits * baseTimeUnit * 0.3
                    
                    call generateMixtureSerial mixStartTime
                    
                    if mixtureDuration > maxDuration
                        maxDuration = mixtureDuration
                    endif
                endfor
                
                currentTime = groupStartTime + maxDuration + baseTimeUnit * 2
            endif
            
            currentTime = currentTime + baseTimeUnit * 0.5
        endfor
        
        currentTime = currentTime + baseTimeUnit * 3
        sectionNum = sectionNum + 1
    endwhile
endif

label DONE_GENERATION

# ========================================================
# Apply light echo/reverb
# ========================================================

selectObject: master
Copy: "dry"
dryObj = selected("Sound")

selectObject: master
Formula: "self * 0.85"

for iTap from 1 to 3
    selectObject: dryObj
    Copy: "tap"
    tapObj = selected("Sound")
    
    delayTime = 0.023 + iTap * 0.017
    decayAmt = 0.65 ^ iTap * 0.12
    
    sampleOffset = round(delayTime * sampleRate)
    Formula: "self[col - " + string$(sampleOffset) + "] * " + string$(decayAmt)
    
    selectObject: master
    Formula: "self + Sound_tap[col]"
    
    removeObject: tapObj
endfor

removeObject: dryObj

# Normalize
selectObject: master
if genMode == 1
    Rename: "studieII_random"
else
    Rename: "studieII_authentic"
endif
Scale peak: 0.97

# Save to file if requested
if doSaveFile
    if genMode == 1
        timestamp$ = string$(round(randomUniform(100000, 999999)))
        filename$ = "studieII_random_" + string$(duration) + "s_" + timestamp$ + ".wav"
    else
        filename$ = "studieII_authentic_" + string$(duration) + "s_rot" + string$(rotationOffset) + ".wav"
    endif
    Save as WAV file: filename$
    writeInfoLine: "Saved to: ", filename$
endif

# Draw score if requested
if doDrawScore
    Erase all
    Select outer viewport: 0, 10, 0, 6
    Black
    Line width: 1
    Font size: 11
    
    Axes: 0, duration, 1, 81
    Draw inner box
    Marks left every: 1, 10, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Pitch Index (Studie II Scale)"
    Text bottom: "yes", "Time (seconds)"
    
    if genMode == 1
        Text top: "no", "STUDIE II (quasi) - RANDOM MODE"
    else
        Text top: "no", "STUDIE II - AUTHENTIC RECONSTRUCTION"
    endif
    
    # Draw light grid
    Grey
    Line width: 0.25
    for t from 1 to duration - 1
        Draw line: t, 1, t, 81
    endfor
    for p from 1 to 8
        pitchLine = p * 10
        Draw line: 0, pitchLine, duration, pitchLine
    endfor
    
    # Draw events
    for iEv from 1 to numStoredEvents
        evStart = eventStart_'iEv'
        evEnd = eventEnd_'iEv'
        
        idx1 = eventIdx1_'iEv'
        idx2 = eventIdx2_'iEv'
        idx3 = eventIdx3_'iEv'
        idx4 = eventIdx4_'iEv'
        idx5 = eventIdx5_'iEv'
        
        minIdx = idx1
        maxIdx = idx5
        
        Grey
        Paint rectangle: "Grey", evStart, evEnd, minIdx - 0.4, maxIdx + 0.4
        
        Black
        Line width: 1.5
        Draw line: evStart, idx1, evEnd, idx1
        Draw line: evStart, idx2, evEnd, idx2
        Draw line: evStart, idx3, evEnd, idx3
        Draw line: evStart, idx4, evEnd, idx4
        Draw line: evStart, idx5, evEnd, idx5
        
        Line width: 2
        Draw rectangle: evStart, evEnd, minIdx - 0.4, maxIdx + 0.4
    endfor
    
    Black
    Line width: 2.5
    Draw inner box
endif

selectObject: master

# ========================================================
# PROCEDURES
# ========================================================

procedure getNextToken
    nextTokenValue = square_'tokenRow'_'tokenCol'
    
    tokenCol = tokenCol + 1
    if tokenCol > 5
        tokenCol = 1
        tokenRow = tokenRow + 1
        if tokenRow > 5
            tokenRow = 1
        endif
    endif
endproc

procedure generateMixtureRandom: .startTime .startIdx .spreadFactor .duration .amplitude .envType
    # Store event for drawing
    if doDrawScore
        numStoredEvents = numStoredEvents + 1
        eventStart_'numStoredEvents' = .startTime
        eventEnd_'numStoredEvents' = .startTime + .duration
        eventIdx1_'numStoredEvents' = .startIdx
        eventIdx2_'numStoredEvents' = .startIdx + .spreadFactor
        eventIdx3_'numStoredEvents' = .startIdx + 2 * .spreadFactor
        eventIdx4_'numStoredEvents' = .startIdx + 3 * .spreadFactor
        eventIdx5_'numStoredEvents' = .startIdx + 4 * .spreadFactor
    endif
    
    # Generate 5 components
    mixtureCreated = 0
    for .comp from 0 to 4
        .idx = .startIdx + .comp * .spreadFactor
        if .idx < 1
            .idx = 1
        elsif .idx > 81
            .idx = 81
        endif
        
        .frequency = freq_'.idx'
        .centerWeight = 1.0 - abs(.comp - 2) * 0.12
        .compAmp = .amplitude * .centerWeight
        
        Create Sound from formula: "component", 1, 0, .duration, sampleRate,
            ... string$(.compAmp) + " * sin(2 * pi * " + string$(.frequency) + " * x)"
        .compObj = selected("Sound")
        
        # Apply envelope
        if .envType == 1
            .att = 0.025
            .rel = 0.018
            Fade in: 0, 0, .att, "yes"
            Fade out: 0, .duration - .rel, .rel, "yes"
        elsif .envType == 2
            .rampEnd = .duration * 0.72
            Formula: "self * min(1, x / " + string$(.rampEnd) + ")"
            Fade out: 0, .duration - 0.01, 0.01, "yes"
        elsif .envType == 3
            .tau = .duration / 2.8
            Formula: "self * exp(-x / " + string$(.tau) + ")"
            Fade in: 0, 0, 0.004, "yes"
        elsif .envType == 4
            .peak = .duration / 2
            Formula: "self * (1 - abs(x - " + string$(.peak) + ") / " + string$(.peak) + ")"
        elsif .envType == 5
            Fade in: 0, 0, 0.003, "yes"
            Fade out: 0, .duration - 0.006, 0.006, "yes"
        else
            .att = .duration * 0.18
            .rel = .duration * 0.22
            Fade in: 0, 0, .att, "yes"
            Fade out: 0, .duration - .rel, .rel, "yes"
        endif
        
        if mixtureCreated == 0
            Rename: "mixture_result"
            .mixtureObj = selected("Sound")
            mixtureCreated = 1
        else
            plusObject: .compObj
            selectObject: .mixtureObj, .compObj
            Combine to stereo
            tempStereo = selected("Sound")
            Convert to mono
            tempMono = selected("Sound")
            
            removeObject: .mixtureObj, .compObj, tempStereo
            selectObject: tempMono
            Rename: "mixture_result"
            .mixtureObj = selected("Sound")
        endif
    endfor
    
    # Add to master
    selectObject: master
    sampleOffset = round(.startTime * sampleRate)
    Formula: "self + Sound_mixture_result[col - " + string$(sampleOffset) + "]"
    
    removeObject: .mixtureObj
endproc

procedure generateMixtureSerial: .startTime
    # Get parameters from serial stream
    call getNextToken
    .spreadFactor = nextTokenValue
    
    call getNextToken
    pitchToken = nextTokenValue
    if pitchToken == 1
        .centerIdx = 15
    elsif pitchToken == 2
        .centerIdx = 28
    elsif pitchToken == 3
        .centerIdx = 41
    elsif pitchToken == 4
        .centerIdx = 54
    else
        .centerIdx = 67
    endif
    
    .idx1 = .centerIdx - 2 * .spreadFactor
    .idx2 = .centerIdx - 1 * .spreadFactor
    .idx3 = .centerIdx
    .idx4 = .centerIdx + 1 * .spreadFactor
    .idx5 = .centerIdx + 2 * .spreadFactor
    
    if .idx1 < 1
        .idx1 = 1
    endif
    if .idx5 > 81
        .idx5 = 81
    endif
    
    call getNextToken
    durToken = nextTokenValue
    mixtureDuration = durMult_'durToken' * baseTimeUnit
    
    if .startTime + mixtureDuration > duration
        mixtureDuration = duration - .startTime
    endif
    
    call getNextToken
    .envType = nextTokenValue
    
    # Calculate loudness
    centerPitchIdx = 41
    distFromCenter = abs(.centerIdx - centerPitchIdx)
    maxDist = 40
    loudnessDB = -30 + (distFromCenter / maxDist) * 30
    .amplitude = 10 ^ (loudnessDB / 20) * 0.25
    
    # Store event
    if doDrawScore
        numStoredEvents = numStoredEvents + 1
        eventStart_'numStoredEvents' = .startTime
        eventEnd_'numStoredEvents' = .startTime + mixtureDuration
        eventIdx1_'numStoredEvents' = .idx1
        eventIdx2_'numStoredEvents' = .idx2
        eventIdx3_'numStoredEvents' = .idx3
        eventIdx4_'numStoredEvents' = .idx4
        eventIdx5_'numStoredEvents' = .idx5
    endif
    
    # Generate 5 components
    mixtureCreated = 0
    for .comp from 1 to 5
        if .comp == 1
            .idx = .idx1
        elsif .comp == 2
            .idx = .idx2
        elsif .comp == 3
            .idx = .idx3
        elsif .comp == 4
            .idx = .idx4
        else
            .idx = .idx5
        endif
        
        .frequency = freq_'.idx'
        .centerWeight = 1.0 - abs(.comp - 3) * 0.08
        .compAmp = .amplitude * .centerWeight
        
        Create Sound from formula: "component", 1, 0, mixtureDuration, sampleRate,
            ... string$(.compAmp) + " * sin(2 * pi * " + string$(.frequency) + " * x)"
        .compObj = selected("Sound")
        
        # Apply envelope
        if .envType == 1
            .att = 0.02
            .rel = 0.015
            Fade in: 0, 0, .att, "yes"
            Fade out: 0, mixtureDuration - .rel, .rel, "yes"
        elsif .envType == 2
            .rampEnd = mixtureDuration * 0.7
            Formula: "self * min(1, x / " + string$(.rampEnd) + ")"
            Fade out: 0, mixtureDuration - 0.01, 0.01, "yes"
        elsif .envType == 3
            .tau = mixtureDuration / 3
            Formula: "self * exp(-x / " + string$(.tau) + ")"
            Fade in: 0, 0, 0.003, "yes"
        elsif .envType == 4
            .peak = mixtureDuration / 2
            Formula: "self * (1 - abs(x - " + string$(.peak) + ") / " + string$(.peak) + ")"
        else
            .att = mixtureDuration * 0.15
            .rel = mixtureDuration * 0.2
            Fade in: 0, 0, .att, "yes"
            Fade out: 0, mixtureDuration - .rel, .rel, "yes"
        endif
        
        if mixtureCreated == 0
            Rename: "mixture_result"
            .mixtureObj = selected("Sound")
            mixtureCreated = 1
        else
            plusObject: .compObj
            selectObject: .mixtureObj, .compObj
            Combine to stereo
            tempStereo = selected("Sound")
            Convert to mono
            tempMono = selected("Sound")
            
            removeObject: .mixtureObj, .compObj, tempStereo
            selectObject: tempMono
            Rename: "mixture_result"
            .mixtureObj = selected("Sound")
        endif
    endfor
    
    # Add to master
    selectObject: master
    sampleOffset = round(.startTime * sampleRate)
    Formula: "self + Sound_mixture_result[col - " + string$(sampleOffset) + "]"
    
    removeObject: .mixtureObj
endproc
Play