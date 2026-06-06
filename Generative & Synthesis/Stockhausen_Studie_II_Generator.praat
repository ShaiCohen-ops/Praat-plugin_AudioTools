# ============================================================
# Praat AudioTools - Stockhausen_Studie_II_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
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
#   Two modes: Random (varied each run) or Serial (Studie II-inspired model)
#
# Reference:
#   Stockhausen, K. (1954). Studie II. Universal Edition.
#
# Changelog v0.3:
#   - Events scale to fill requested duration; improved timing accuracy
#
# Changelog v0.4:
#   - FIXED reverb: each tap was a Copy of the dry signal modified in place with
#     self[col-offset], which reads already-overwritten samples and cascaded the
#     entire tap to zero, so the "Light Reverb" added nothing. Taps now read the
#     unmodified dry signal (feedforward), producing real attenuated echoes.
#   - Score visualization aligned to the AudioTools house style (8-inch canvas,
#     title band, grey {0.94} summary, full-precision RGB).
#   - Replaced non-ASCII characters (multiplication signs, em-dashes).
#
# Changelog v0.5:
#   - Reworked the serial mode toward the documented Studie II method and
#     relabelled it honestly as "Studie II-inspired" (it is a model of the
#     method, not a transcription of the actual score):
#       * Section-type sequence now follows the documented pattern
#         (horizontal-linked / vertical / horizontal-separated / vertical /
#         combination) instead of an arbitrary order.
#       * Added the group level (section -> subsection -> group -> sounds);
#         each group holds its mixture WIDTH constant, changing group to group.
#       * Mixtures are now five sine tones EQUALLY SPACED IN Hz (the Studie II
#         construction, which yields the inharmonic timbre), with the Hz step
#         derived from the 5^(1/25) scale - replacing the old equal-scale-step
#         (geometric) spacing.
#     The serial number-square here is still a model; the authentic series is
#     documented in Silberhorn (1978) and Williams (2016).
#   - Added a Wet_only_reverb option modelling Studie II's wet-only treatment
#     (dry transient removed, soft blurred attacks).
#
# Changelog v0.6:
#   - Fixed the trivial periodicity: the token reader walked the 5x5 square and
#     wrapped every 25 tokens, so the serial output looped (the same group
#     pattern repeated identically). It now applies standard serial operations
#     per pass (row rotation + inversion + transposition), extending the period
#     to ~500 tokens so the material develops instead of looping.
#   - Fixed the score layout: the grey summary collided with the time-axis
#     label; the score area was raised and the summary moved clear below it.
# ============================================================

form Studie II Generator
    comment === Generation Mode ===
    optionmenu Generation_mode 1
        option Random (varied each time)
        option Serial (Studie II-inspired)
    
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
    boolean Wet_only_reverb 0
    
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
    appendInfoLine: "Mode: Serial (Studie II-inspired)"
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
    for rowNum to 5
        for colNum to 5
            srcCol = ((colNum - 1 + rowNum - 1) mod 5) + 1
            square[rowNum, colNum] = seed[srcCol]
        endfor
    endfor
    
    # Duration multipliers (1, 2, 4, 8, 16 x base unit)
    durMult[1] = 1
    durMult[2] = 2
    durMult[3] = 4
    durMult[4] = 8
    durMult[5] = 16
    
    # Token stream position
    tokenRow = 1 + (abs(rotation_offset) mod 5)
    tokenCol = 1
    tokenPass = 0
    
    # Section types
    sectionType[1] = 1
    sectionType[2] = 2
    sectionType[3] = 3
    sectionType[4] = 4
    sectionType[5] = 5
endif

# === Create Temporary Master Sound (will be recreated after timing adjustment) ===
master = Create Sound from formula: "master_temp_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Event Storage ===
numEvents = 0
maxStoredEvents = 500

# Pre-allocate arrays
for i to maxStoredEvents
    evStart[i] = 0
    evEnd[i] = 0
    evDur[i] = 0
    evAmp[i] = 0
    evEnv[i] = 0
    for c to 5
        evFreq[i, c] = 0
    endfor
endfor

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
                evDuration = randomUniform(0.08, 0.45)
                
                if currentTime + evDuration > duration_s
                    evDuration = duration_s - currentTime
                endif
                
                evAmplitude = randomUniform(min_amplitude, max_amplitude)
                envType = randomInteger(1, 5)
                
                @storeEvent: currentTime, evDuration, startIdx, spreadFactor, evAmplitude, envType
                
                currentTime = currentTime + evDuration + randomUniform(0.005, 0.06)
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
                evDuration = randomUniform(groupLen * 0.6, groupLen * 1.3)
                evStart = groupStart + randomUniform(0, groupLen * 0.25)
                
                if evStart + evDuration > duration_s
                    evDuration = duration_s - evStart
                endif
                
                if evDuration >= 0.03
                    evAmplitude = randomUniform(min_amplitude, max_amplitude)
                    envType = randomInteger(1, 5)
                    @storeEvent: evStart, evDuration, startIdx, spreadFactor, evAmplitude, envType
                endif
            endfor
            
            label skipVertical
            currentTime = groupStart + groupLen + randomUniform(0.01, 0.12)
        endif
        
        appendInfoLine: "  Group ", iGroup, "/", num_groups
    endfor

else
    # ========================================
    # SERIAL MODE (Studie II-inspired model)
    # ========================================
    # Hierarchy: 5 sections x 5 subsections x 5 groups x (1-5 sounds).
    # Mixture width is held constant within a group and changes group to group.
    # Section types follow the documented Studie II pattern:
    #   1 horizontal linked | 2 vertical | 3 horizontal separated |
    #   4 vertical | 5 combination of horizontal and vertical.
    # Generation stops when the requested duration is filled, so short durations
    # show the opening sections and longer durations traverse more of the form.
    
    sectionNum = 1
    
    while currentTime < duration_s and sectionNum <= 5
        secType = sectionType[sectionNum]
        
        for subsectionNum to 5
            if currentTime >= duration_s
                goto doneGeneration
            endif
            
            for groupNum to 5
                if currentTime >= duration_s or numEvents >= maxStoredEvents
                    goto doneGeneration
                endif
                
                # Mixture width for this group (constant within the group)
                @getNextToken
                groupWidth = getNextToken.value
                
                # Number of sounds in this group (1-5)
                @getNextToken
                numSounds = getNextToken.value
                
                # Resolve horizontal/vertical behaviour for this group
                if secType = 1
                    localType = 1
                elsif secType = 2
                    localType = 3
                elsif secType = 3
                    localType = 2
                elsif secType = 4
                    localType = 3
                else
                    if (groupNum mod 2) = 1
                        localType = 1
                    else
                        localType = 3
                    endif
                endif
                
                if localType = 1
                    # Horizontal, linked
                    for iSound to numSounds
                        if currentTime >= duration_s
                            goto doneGeneration
                        endif
                        @storeEventSerial: currentTime, groupWidth
                        currentTime = currentTime + storeEventSerial.duration
                    endfor
                elsif localType = 2
                    # Horizontal, separated by silences
                    for iSound to numSounds
                        if currentTime >= duration_s
                            goto doneGeneration
                        endif
                        @storeEventSerial: currentTime, groupWidth
                        currentTime = currentTime + storeEventSerial.duration
                        @getNextToken
                        gapUnits = getNextToken.value
                        currentTime = currentTime + gapUnits * baseTimeUnit * 0.5
                    endfor
                else
                    # Vertical (overlapping)
                    groupStartTime = currentTime
                    maxDuration = 0
                    for iSound to numSounds
                        @getNextToken
                        staggerUnits = getNextToken.value
                        mixStartTime = groupStartTime + staggerUnits * baseTimeUnit * 0.3
                        @storeEventSerial: mixStartTime, groupWidth
                        if storeEventSerial.duration > maxDuration
                            maxDuration = storeEventSerial.duration
                        endif
                    endfor
                    currentTime = groupStartTime + maxDuration + baseTimeUnit * 2
                endif
                
                currentTime = currentTime + baseTimeUnit * 0.5
            endfor
        endfor
        
        currentTime = currentTime + baseTimeUnit * 3
        sectionNum = sectionNum + 1
    endwhile
endif

label doneGeneration

appendInfoLine: "Generated ", numEvents, " mixture events"

# ============================================================
# TIMING ADJUSTMENT - SCALE TO FIT DURATION
# ============================================================

# Find actual span of events
actualEndTime = 0
for i to numEvents
    if evEnd[i] > actualEndTime
        actualEndTime = evEnd[i]
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Adjusting timing to fit ", duration_s, " seconds..."
appendInfoLine: "  Generated span: ", fixed$(actualEndTime, 2), " s"

if actualEndTime > 0 and actualEndTime < duration_s
    # Scale all times to fill the duration
    timeScale = (duration_s * 0.98) / actualEndTime
    
    appendInfoLine: "  Time scaling: ", fixed$(timeScale, 3), "x"
    
    for i to numEvents
        evStart[i] = evStart[i] * timeScale
        evEnd[i] = evEnd[i] * timeScale
        evDur[i] = evDur[i] * timeScale
    endfor
    
    actualEndTime = actualEndTime * timeScale
    appendInfoLine: "  Adjusted span: ", fixed$(actualEndTime, 2), " s"
elsif actualEndTime > duration_s
    # Scale down if exceeded
    timeScale = (duration_s * 0.98) / actualEndTime
    
    appendInfoLine: "  Time scaling: ", fixed$(timeScale, 3), "x"
    
    for i to numEvents
        evStart[i] = evStart[i] * timeScale
        evEnd[i] = evEnd[i] * timeScale
        evDur[i] = evDur[i] * timeScale
    endfor
    
    actualEndTime = actualEndTime * timeScale
    appendInfoLine: "  Adjusted span: ", fixed$(actualEndTime, 2), " s"
endif

# ============================================================
# RENDER AUDIO WITH SCALED TIMES
# ============================================================

appendInfoLine: ""
appendInfoLine: "Rendering audio..."

# Remove temporary master and create final one
removeObject: master
master = Create Sound from formula: "master_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Render all events with scaled times
for i to numEvents
    @renderMixture: i
    
    if (i mod 20) = 0
        appendInfoLine: "  Rendered ", i, "/", numEvents
    endif
endfor

appendInfoLine: "Rendering complete"

# === Reverberation ===
selectObject: master
Copy: "dry_" + uid$
dryObj = selected("Sound")

if wet_only_reverb
    # Studie II character: keep ONLY the reverberated (wet) signal with the dry
    # transient removed, giving soft, blurred attacks. Modelled as a dense
    # cluster of attenuated, delayed copies of the dry signal (no dry kept).
    appendInfoLine: "Applying wet-only reverb (Studie II character)..."
    selectObject: master
    Formula: "0"
    for iTap to 12
        delayTime = 0.012 + iTap * 0.011
        decayAmt = exp(-iTap * 0.30) * 0.6
        sampleOffset = round(delayTime * sample_rate_Hz)
        selectObject: master
        Formula: "self + if col > " + string$(sampleOffset) + " then Sound_dry_" + uid$ + "[col - " + string$(sampleOffset) + "] * " + string$(decayAmt) + " else 0 fi"
    endfor
    # Soft fade-in (the sharp dry onset is gone)
    fadeSamp = round(0.02 * sample_rate_Hz)
    selectObject: master
    Formula: "if col < fadeSamp then self * (col / fadeSamp) else self fi"
else
    # Dry plus a light reverb tail (feedforward echoes)
    appendInfoLine: "Applying light reverb..."
    selectObject: master
    Formula: "self * 0.85"
    for iTap to 3
        delayTime = 0.023 + iTap * 0.017
        decayAmt = 0.65 ^ iTap * 0.12
        sampleOffset = round(delayTime * sample_rate_Hz)
        selectObject: master
        Formula: "self + if col > " + string$(sampleOffset) + " then Sound_dry_" + uid$ + "[col - " + string$(sampleOffset) + "] * " + string$(decayAmt) + " else 0 fi"
    endfor
endif

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
    # Read the 5x5 square, but apply a serial transformation that changes each
    # completed pass (row rotation + inversion + transposition), so the token
    # stream develops over ~500 tokens instead of looping every 25.
    .rr = ((tokenRow - 1 + tokenPass) mod 5) + 1
    .v = square[.rr, tokenCol]
    .pmod = tokenPass mod 4
    if .pmod = 1
        .v = 6 - .v
    elsif .pmod = 2
        .v = square[tokenCol, .rr]
    elsif .pmod = 3
        .v = 6 - square[tokenCol, .rr]
    endif
    .value = .v
    
    tokenCol = tokenCol + 1
    if tokenCol > 5
        tokenCol = 1
        tokenRow = tokenRow + 1
        if tokenRow > 5
            tokenRow = 1
            tokenPass = tokenPass + 1
        endif
    endif
endproc

# ==============================================================================
# Procedure: storeEvent (Random Mode)
# ==============================================================================
procedure storeEvent: .startTime, .duration, .startIdx, .spreadFactor, .amplitude, .envType
    
    numEvents = numEvents + 1
    
    evStart[numEvents] = .startTime
    evEnd[numEvents] = .startTime + .duration
    evDur[numEvents] = .duration
    evAmp[numEvents] = .amplitude
    evEnv[numEvents] = .envType
    
    for .c to 5
        .ix = .startIdx + (.c - 1) * .spreadFactor
        if .ix < 1
            .ix = 1
        endif
        if .ix > 81
            .ix = 81
        endif
        evFreq[numEvents, .c] = freq[.ix]
    endfor
endproc

# ==============================================================================
# Procedure: storeEventSerial (Serial Mode)
# ==============================================================================
procedure storeEventSerial: .startTime, .spreadFactor
    
    # Pitch register (one of five) from the token stream
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
    .centerFreq = freq[.centerIdx]
    
    # Five sine tones EQUALLY SPACED IN Hz (the Studie II mixture construction,
    # which produces the characteristic inharmonic timbre). The Hz step is
    # derived from the 5^(1/25) scale, so the five mixture widths come from the
    # same scale as the pitches.
    .stepHz = .centerFreq * (5 ^ (.spreadFactor / 25) - 1)
    .fc[1] = .centerFreq - 2 * .stepHz
    .fc[2] = .centerFreq - 1 * .stepHz
    .fc[3] = .centerFreq
    .fc[4] = .centerFreq + 1 * .stepHz
    .fc[5] = .centerFreq + 2 * .stepHz
    
    # Get duration
    @getNextToken
    .durToken = getNextToken.value
    .duration = durMult[.durToken] * baseTimeUnit
    
    # Get amplitude
    @getNextToken
    .ampToken = getNextToken.value
    .amplitude = min_amplitude + (.ampToken - 1) / 4 * (max_amplitude - min_amplitude)
    
    # Get envelope
    @getNextToken
    .envType = getNextToken.value
    
    # Store event
    numEvents = numEvents + 1
    
    evStart[numEvents] = .startTime
    evEnd[numEvents] = .startTime + .duration
    evDur[numEvents] = .duration
    evAmp[numEvents] = .amplitude
    evEnv[numEvents] = .envType
    
    for .c to 5
        .ff = .fc[.c]
        if .ff < 30
            .ff = 30
        endif
        if .ff > sample_rate_Hz / 2 - 100
            .ff = sample_rate_Hz / 2 - 100
        endif
        evFreq[numEvents, .c] = .ff
    endfor
endproc

# ==============================================================================
# Procedure: renderMixture
# ==============================================================================
procedure renderMixture: .eventNum
    
    .startTime = evStart[.eventNum]
    .duration = evDur[.eventNum]
    .amplitude = evAmp[.eventNum]
    .envType = evEnv[.eventNum]
    
    # Create mixture sound
    .mixSound = Create Sound from formula: "mix_" + uid$, 1, 0, .duration, sample_rate_Hz, "0"
    
    # Add 5 frequency components
    for .comp to 5
        .frequency = evFreq[.eventNum, .comp]
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
        .att = min(0.025, .duration * 0.2)
        .rel = min(0.018, .duration * 0.15)
        Fade in: 0, 0, .att, "yes"
        Fade out: 0, .duration - .rel, .rel, "yes"
    elsif .envType = 2
        .rampEnd = .duration * 0.72
        Formula: "self * min(1, x / " + fixed$(.rampEnd, 4) + ")"
        Fade out: 0, .duration - 0.01, 0.01, "yes"
    elsif .envType = 3
        .tau = .duration / 2.8
        Formula: "self * exp(-x / " + fixed$(.tau, 4) + ")"
        Fade in: 0, 0, 0.004, "yes"
    elsif .envType = 4
        .peak = .duration / 2
        Formula: "self * (1 - abs(x - " + fixed$(.peak, 4) + ") / " + fixed$(.peak, 4) + ")"
    else
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
# Procedure: drawScore
# ==============================================================================
procedure drawScore

    Erase all

    # === Title (own clear band) ===
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    if generation_mode = 1
        Text: 0.5, "centre", 0.5, "half", "Studie II (quasi): Random Mode"
    else
        Text: 0.5, "centre", 0.5, "half", "Studie II: Serial Model"
    endif

    # === Score area ===
    Select outer viewport: 0, 8, 0.9, 4.9
    Select inner viewport: 0.75, 7.6, 1.05, 4.8
    Axes: 0, duration_s, 1, 81

    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 0.5
    .t = 1
    while .t <= floor(duration_s)
        Draw line: .t, 1, .t, 81
        .t = .t + 1
    endwhile
    .p = 1
    while .p <= 8
        .pitchLine = .p * 10
        Draw line: 0, .pitchLine, duration_s, .pitchLine
        .p = .p + 1
    endwhile

    # Events
    for .ev to numEvents
        .eStart = evStart[.ev]
        .eEnd = evEnd[.ev]
        .minIdx = 1 + 25 * ln(evFreq[.ev, 1] / base_frequency_Hz) / ln(5)
        .maxIdx = 1 + 25 * ln(evFreq[.ev, 5] / base_frequency_Hz) / ln(5)
        Paint rectangle: "{0.90, 0.90, 0.95}", .eStart, .eEnd, .minIdx - 0.4, .maxIdx + 0.4
        Colour: "{0.20, 0.30, 0.60}"
        Line width: 1.5
        for .c to 5
            .idxc = 1 + 25 * ln(evFreq[.ev, .c] / base_frequency_Hz) / ln(5)
            Draw line: .eStart, .idxc, .eEnd, .idxc
        endfor
        Colour: "{0.40, 0.40, 0.50}"
        Line width: 1
        Draw rectangle: .eStart, .eEnd, .minIdx - 0.4, .maxIdx + 0.4
    endfor

    Colour: "Black"
    Line width: 1.5
    Draw inner box
    Font size: 9
    Marks left every: 1, 10, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "Pitch Index (81-tone scale)"
    Text bottom: "yes", "Time (s)"

    # === Summary panel (grey) ===
    Select outer viewport: 0, 8, 5.6, 6.0
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Scale: 5^(1/25) ratio | Range: " + fixed$(freq[1], 0) + " - " + fixed$(freq[81], 0) + " Hz | Events: " + string$(numEvents)
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc