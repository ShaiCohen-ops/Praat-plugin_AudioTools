# ============================================================
# Praat AudioTools - Stockhausen_Studie_II_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generator inspired by Karlheinz Stockhausen's Studie II (1954),
#   one of the first fully electronic compositions. Implements:
#   - 81-tone scale based on 5^(1/25) ratio (~1.066)
#   - 5-tone mixtures (equally-spaced frequency groups)
#   - Serial organization via Latin square permutations
#   - 5 envelope types
#   - Score visualization in Studie II notation style
#
#   Two modes: Random (varied each run) or Serial (authentic)
#
# Reference:
#   Stockhausen, K. (1954). Studie II. Universal Edition.
#
# Changelog v0.2:
#   - Optimized mixture generation
#   - Modern syntax
#   - Improved score visualization
#   - Fixed 'col' variable conflict
# ============================================================

form Studie II Generator
    comment === Generation Mode ===
    optionmenu Generation_mode 1
        option Random (varied each time)
        option Serial (authentic reconstruction)
    
    comment === Composition Parameters ===
    positive Duration_s 10.0
    positive Num_groups 7
    
    comment === Audio Settings ===
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    
    comment === Amplitude Range ===
    positive Min_amplitude 0.10
    positive Max_amplitude 0.30
    
    comment === Options ===
    boolean Draw_score 1
    boolean Play_result 1
    
    comment === Serial Mode: rotation offset (0 = beginning) ===
    integer Rotation_offset 0
endform

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
baseTimeUnit = 0.0328

# === Build 81-Tone Frequency Scale ===
# Studie II uses 5^(1/25) ratio between adjacent tones
# This creates 81 frequencies spanning ~5 octaves

for i to 81
    freq[i] = base_frequency_Hz * (5 ^ ((i - 1) / 25))
endfor

# === Info ===
writeInfoLine: "=== Stockhausen Studie II Generator ==="
if generation_mode = 1
    appendInfoLine: "Mode: Random (quasi-Studie II)"
else
    appendInfoLine: "Mode: Serial (authentic)"
endif
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Frequency range: ", fixed$(freq[1], 1), " - ", fixed$(freq[81], 1), " Hz"
appendInfoLine: "Scale ratio: 5^(1/25) = ", fixed$(5^(1/25), 4)
appendInfoLine: ""

# === Serial Mode Setup ===
if generation_mode = 2
    # Primary seed row (Stockhausen's input series)
    seed[1] = 3
    seed[2] = 5
    seed[3] = 1
    seed[4] = 4
    seed[5] = 2
    
    # Generate 5x5 Latin square
    # NOTE: Use 'colNum' not 'col' to avoid conflict with Formula's built-in col
    for rowNum to 5
        for colNum to 5
            srcCol = ((colNum - 1 + rowNum - 1) mod 5) + 1
            square[rowNum, colNum] = seed[srcCol]
        endfor
    endfor
    
    # Duration multipliers (1, 2, 4, 8, 16 × base unit)
    durMult[1] = 1
    durMult[2] = 2
    durMult[3] = 4
    durMult[4] = 8
    durMult[5] = 16
    
    # Token stream position
    tokenRow = 1 + (abs(rotation_offset) mod 5)
    tokenCol = 1
    
    # Section types
    sectionType[1] = 1
    sectionType[2] = 2
    sectionType[3] = 3
    sectionType[4] = 1
    sectionType[5] = 2
endif

# === Create Master Sound ===
master = Create Sound from formula: "master_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Event Storage for Score ===
numEvents = 0

# === Main Generation ===
appendInfoLine: "Generating..."

currentTime = 0

if generation_mode = 1
    # ========================================
    # RANDOM MODE
    # ========================================
    
    for iGroup to num_groups
        if currentTime >= duration_s - 0.05
            goto doneGeneration
        endif
        
        groupType = randomInteger(0, 1)
        numMixtures = randomInteger(1, 5)
        
        if groupType = 0
            # Horizontal: sequential events
            for iMix to numMixtures
                if currentTime >= duration_s - 0.05
                    goto doneGeneration
                endif
                
                spreadFactor = randomInteger(1, 5)
                startIdx = randomInteger(10, 65 - 4 * spreadFactor)
                evDur = randomUniform(0.08, 0.45)
                
                if currentTime + evDur > duration_s
                    evDur = duration_s - currentTime
                endif
                
                evAmp = randomUniform(min_amplitude, max_amplitude)
                envType = randomInteger(1, 5)
                
                @generateMixture: currentTime, startIdx, spreadFactor, evDur, evAmp, envType
                
                currentTime = currentTime + evDur + randomUniform(0.005, 0.06)
            endfor
            
            if randomUniform(0, 1) > 0.4
                currentTime = currentTime + randomUniform(0.03, 0.25)
            endif
        else
            # Vertical: overlapping events
            groupStart = currentTime
            groupLen = randomUniform(0.25, 0.7)
            
            for iMix to numMixtures
                if groupStart >= duration_s - 0.05
                    goto skipVertical
                endif
                
                spreadFactor = randomInteger(1, 5)
                startIdx = randomInteger(10, 65 - 4 * spreadFactor)
                evDur = randomUniform(groupLen * 0.6, groupLen * 1.3)
                evStart = groupStart + randomUniform(0, groupLen * 0.25)
                
                if evStart + evDur > duration_s
                    evDur = duration_s - evStart
                endif
                
                if evDur >= 0.03
                    evAmp = randomUniform(min_amplitude, max_amplitude)
                    envType = randomInteger(1, 5)
                    @generateMixture: evStart, startIdx, spreadFactor, evDur, evAmp, envType
                endif
            endfor
            
            label skipVertical
            currentTime = groupStart + groupLen + randomUniform(0.01, 0.12)
        endif
        
        appendInfoLine: "  Group ", iGroup, "/", num_groups
    endfor

else
    # ========================================
    # SERIAL MODE (Authentic)
    # ========================================
    
    sectionNum = 1
    
    while currentTime < duration_s and sectionNum <= 5
        secType = sectionType[sectionNum]
        
        for subsectionNum to 5
            if currentTime >= duration_s
                goto doneGeneration
            endif
            
            @getNextToken
            numMixtures = getNextToken.value
            
            if secType = 1
                # Horizontal linked
                for iMix to numMixtures
                    if currentTime >= duration_s
                        goto doneGeneration
                    endif
                    
                    @generateMixtureSerial: currentTime
                    currentTime = currentTime + generateMixtureSerial.duration
                endfor
                
            elsif secType = 2
                # Horizontal separated
                for iMix to numMixtures
                    if currentTime >= duration_s
                        goto doneGeneration
                    endif
                    
                    @generateMixtureSerial: currentTime
                    currentTime = currentTime + generateMixtureSerial.duration
                    
                    @getNextToken
                    gapUnits = getNextToken.value
                    currentTime = currentTime + gapUnits * baseTimeUnit * 0.5
                endfor
                
            else
                # Vertical (overlapping)
                groupStartTime = currentTime
                maxDuration = 0
                
                for iMix to numMixtures
                    if currentTime >= duration_s
                        goto doneGeneration
                    endif
                    
                    @getNextToken
                    staggerUnits = getNextToken.value
                    mixStartTime = groupStartTime + staggerUnits * baseTimeUnit * 0.3
                    
                    @generateMixtureSerial: mixStartTime
                    
                    if generateMixtureSerial.duration > maxDuration
                        maxDuration = generateMixtureSerial.duration
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

label doneGeneration

appendInfoLine: "Generated ", numEvents, " mixture events"

# === Apply Light Reverb ===
appendInfoLine: "Applying reverb..."

selectObject: master
Copy: "dry_" + uid$
dryObj = selected("Sound")

selectObject: master
Formula: "self * 0.85"

for iTap to 3
    selectObject: dryObj
    Copy: "tap_" + uid$
    tapObj = selected("Sound")
    
    delayTime = 0.023 + iTap * 0.017
    decayAmt = 0.65 ^ iTap * 0.12
    
    sampleOffset = round(delayTime * sample_rate_Hz)
    Formula: "self[col - " + string$(sampleOffset) + "] * " + string$(decayAmt)
    
    selectObject: master
    Formula: "self + Sound_tap_" + uid$ + "[col]"
    
    removeObject: tapObj
endfor

removeObject: dryObj

# === Normalize ===
selectObject: master
if generation_mode = 1
    Rename: "studieII_random"
else
    Rename: "studieII_serial"
endif
Scale peak: 0.95

outputSound = selected("Sound")

# === Draw Score ===
if draw_score
    appendInfoLine: ""
    appendInfoLine: "Drawing score..."
    @drawScore
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: getNextToken
# ==============================================================================
procedure getNextToken
    .value = square[tokenRow, tokenCol]
    
    tokenCol = tokenCol + 1
    if tokenCol > 5
        tokenCol = 1
        tokenRow = tokenRow + 1
        if tokenRow > 5
            tokenRow = 1
        endif
    endif
endproc

# ==============================================================================
# Procedure: generateMixture (Random Mode)
# ==============================================================================
procedure generateMixture: .startTime, .startIdx, .spreadFactor, .duration, .amplitude, .envType
    
    # Store event for score
    numEvents = numEvents + 1
    evStart[numEvents] = .startTime
    evEnd[numEvents] = .startTime + .duration
    for .c to 5
        evIdx[numEvents, .c] = .startIdx + (.c - 1) * .spreadFactor
        if evIdx[numEvents, .c] < 1
            evIdx[numEvents, .c] = 1
        endif
        if evIdx[numEvents, .c] > 81
            evIdx[numEvents, .c] = 81
        endif
    endfor
    
    # Create mixture sound
    .mixSound = Create Sound from formula: "mix_" + uid$, 1, 0, .duration, sample_rate_Hz, "0"
    
    # Add 5 frequency components
    for .comp to 5
        .idx = .startIdx + (.comp - 1) * .spreadFactor
        if .idx < 1
            .idx = 1
        endif
        if .idx > 81
            .idx = 81
        endif
        
        .frequency = freq[.idx]
        # Center-weighted amplitude (middle component loudest)
        .centerWeight = 1.0 - abs(.comp - 3) * 0.12
        .compAmp = .amplitude * .centerWeight
        
        .compAmp$ = fixed$(.compAmp, 5)
        .freq$ = fixed$(.frequency, 2)
        
        selectObject: .mixSound
        Formula: "self + " + .compAmp$ + " * sin(twoPi * " + .freq$ + " * x)"
    endfor
    
    # Apply envelope
    selectObject: .mixSound
    if .envType = 1
        # Attack-decay
        .att = min(0.025, .duration * 0.2)
        .rel = min(0.018, .duration * 0.15)
        Fade in: 0, 0, .att, "yes"
        Fade out: 0, .duration - .rel, .rel, "yes"
    elsif .envType = 2
        # Ramp up
        .rampEnd = .duration * 0.72
        Formula: "self * min(1, x / " + fixed$(.rampEnd, 4) + ")"
        Fade out: 0, .duration - 0.01, 0.01, "yes"
    elsif .envType = 3
        # Exponential decay
        .tau = .duration / 2.8
        Formula: "self * exp(-x / " + fixed$(.tau, 4) + ")"
        Fade in: 0, 0, 0.004, "yes"
    elsif .envType = 4
        # Triangle
        .peak = .duration / 2
        Formula: "self * (1 - abs(x - " + fixed$(.peak, 4) + ") / " + fixed$(.peak, 4) + ")"
    else
        # Short attack-release
        Fade in: 0, 0, 0.003, "yes"
        Fade out: 0, .duration - 0.006, 0.006, "yes"
    endif
    
    # Add to master at correct time position
    .sampleOffset = round(.startTime * sample_rate_Hz)
    
    selectObject: master
    Formula: "self + Sound_mix_" + uid$ + "[col - " + string$(.sampleOffset) + "]"
    
    removeObject: .mixSound
endproc

# ==============================================================================
# Procedure: generateMixtureSerial (Serial Mode)
# ==============================================================================
procedure generateMixtureSerial: .startTime
    
    # Get spread factor from token stream
    @getNextToken
    .spreadFactor = getNextToken.value
    
    # Get pitch register
    @getNextToken
    .pitchToken = getNextToken.value
    if .pitchToken = 1
        .centerIdx = 15
    elsif .pitchToken = 2
        .centerIdx = 28
    elsif .pitchToken = 3
        .centerIdx = 41
    elsif .pitchToken = 4
        .centerIdx = 54
    else
        .centerIdx = 67
    endif
    
    # Calculate 5 frequency indices (centered)
    .idx[1] = .centerIdx - 2 * .spreadFactor
    .idx[2] = .centerIdx - 1 * .spreadFactor
    .idx[3] = .centerIdx
    .idx[4] = .centerIdx + 1 * .spreadFactor
    .idx[5] = .centerIdx + 2 * .spreadFactor
    
    for .c to 5
        if .idx[.c] < 1
            .idx[.c] = 1
        endif
        if .idx[.c] > 81
            .idx[.c] = 81
        endif
    endfor
    
    # Get duration
    @getNextToken
    .durToken = getNextToken.value
    .duration = durMult[.durToken] * baseTimeUnit
    
    if .startTime + .duration > duration_s
        .duration = duration_s - .startTime
    endif
    
    # Get envelope type
    @getNextToken
    .envType = getNextToken.value
    
    # Calculate amplitude (pitch-dependent loudness)
    .centerPitchIdx = 41
    .distFromCenter = abs(.centerIdx - .centerPitchIdx)
    .maxDist = 40
    .loudnessDB = -30 + (.distFromCenter / .maxDist) * 30
    .amplitude = 10 ^ (.loudnessDB / 20) * 0.25
    
    # Store event
    numEvents = numEvents + 1
    evStart[numEvents] = .startTime
    evEnd[numEvents] = .startTime + .duration
    for .c to 5
        evIdx[numEvents, .c] = .idx[.c]
    endfor
    
    # Create mixture sound
    .mixSound = Create Sound from formula: "mix_" + uid$, 1, 0, .duration, sample_rate_Hz, "0"
    
    # Add 5 components
    for .comp to 5
        .frequency = freq[.idx[.comp]]
        .centerWeight = 1.0 - abs(.comp - 3) * 0.08
        .compAmp = .amplitude * .centerWeight
        
        .compAmp$ = fixed$(.compAmp, 5)
        .freq$ = fixed$(.frequency, 2)
        
        selectObject: .mixSound
        Formula: "self + " + .compAmp$ + " * sin(twoPi * " + .freq$ + " * x)"
    endfor
    
    # Apply envelope
    selectObject: .mixSound
    if .envType = 1
        .att = min(0.02, .duration * 0.2)
        .rel = min(0.015, .duration * 0.15)
        Fade in: 0, 0, .att, "yes"
        Fade out: 0, .duration - .rel, .rel, "yes"
    elsif .envType = 2
        .rampEnd = .duration * 0.7
        Formula: "self * min(1, x / " + fixed$(.rampEnd, 4) + ")"
        Fade out: 0, .duration - 0.01, 0.01, "yes"
    elsif .envType = 3
        .tau = .duration / 3
        Formula: "self * exp(-x / " + fixed$(.tau, 4) + ")"
        Fade in: 0, 0, 0.003, "yes"
    elsif .envType = 4
        .peak = .duration / 2
        Formula: "self * (1 - abs(x - " + fixed$(.peak, 4) + ") / " + fixed$(.peak, 4) + ")"
    else
        .att = .duration * 0.15
        .rel = .duration * 0.2
        Fade in: 0, 0, .att, "yes"
        Fade out: 0, .duration - .rel, .rel, "yes"
    endif
    
    # Add to master
    .sampleOffset = round(.startTime * sample_rate_Hz)
    
    selectObject: master
    Formula: "self + Sound_mix_" + uid$ + "[col - " + string$(.sampleOffset) + "]"
    
    removeObject: .mixSound
endproc

# ==============================================================================
# Procedure: drawScore
# ==============================================================================
procedure drawScore
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 12
    Colour: "Black"
    if generation_mode = 1
        Text: 0.5, "centre", 0.5, "half", "STUDIE II (quasi) — Random Mode"
    else
        Text: 0.5, "centre", 0.5, "half", "STUDIE II — Serial Reconstruction"
    endif
    
    # === Score Area ===
    Select outer viewport: 0, 10, 0.7, 6
    Select inner viewport: 0.8, 9.5, 0.9, 5.8
    
    Axes: 0, duration_s, 1, 81
    
    # Draw grid
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 0.5
    
    # Time grid
    for .t to floor(duration_s)
        Draw line: .t, 1, .t, 81
    endfor
    
    # Pitch grid (every 10 indices)
    for .p to 8
        .pitchLine = .p * 10
        Draw line: 0, .pitchLine, duration_s, .pitchLine
    endfor
    
    # Draw events
    for .ev to numEvents
        .eStart = evStart[.ev]
        .eEnd = evEnd[.ev]
        
        .minIdx = evIdx[.ev, 1]
        .maxIdx = evIdx[.ev, 5]
        
        # Background rectangle
        Colour: "{0.9, 0.9, 0.95}"
        Paint rectangle: "{0.9, 0.9, 0.95}", .eStart, .eEnd, .minIdx - 0.4, .maxIdx + 0.4
        
        # 5 frequency lines
        Colour: "{0.2, 0.3, 0.6}"
        Line width: 1.5
        for .c to 5
            .idx = evIdx[.ev, .c]
            Draw line: .eStart, .idx, .eEnd, .idx
        endfor
        
        # Border
        Colour: "{0.4, 0.4, 0.5}"
        Line width: 1
        Draw rectangle: .eStart, .eEnd, .minIdx - 0.4, .maxIdx + 0.4
    endfor
    
    # Axes
    Colour: "Black"
    Line width: 1.5
    Draw inner box
    
    Font size: 9
    Marks left every: 1, 10, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Pitch Index (81-tone scale)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 10, 6, 6.5
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Scale: 5^(1/25) ratio | Range: " + fixed$(freq[1], 0) + " - " + fixed$(freq[81], 0) + " Hz | Events: " + string$(numEvents)
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc