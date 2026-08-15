# ============================================================
# Praat AudioTools - Stockhausen_Studie_II_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generator inspired by Karlheinz Stockhausen's Studie II (1954).
#   Serial mode is a historically informed MODEL, not a transcription.
#   Core materials:
#   - idealized 81-tone scale based on 5^(1/25)
#   - five-component Tongemische selected by 1..5 SCALE STEPS
#   - section/group organization inspired by the documented five-part form
#   - monochrome, two-system score visualization informed by the published score:
#       upper system = 81-line tone-mixture field
#       centre strip = tape-time / duration information
#       lower system = articulation and amplitude envelopes
#
# Changelog v0.8:
#   SOURCES CHECKED against Toop 2005 (in Six Lectures from the Stockhausen
#   Courses Kürten 2002), Stockhausen Texte 2, and the score preface as
#   reported by Llorente and Krzyzaniak.
#   - CONFIRMED CORRECT: the 81-degree scale on 5^(1/25) from 100 Hz to
#     ~17.2 kHz; the 5 sections x 5 subsections x 5 groups x 1-5 sounds
#     hierarchy; mixture width held constant within a group and changing
#     from group to group; five-sine mixtures spaced by 1-5 SCALE DEGREES,
#     i.e. geometric in Hz. Some secondary sources describe the mixtures as
#     equally spaced in Hz; that reading is inconsistent with a scale whose
#     step is a fixed ratio, and the arithmetic examples they give are
#     rounded oscillator settings. v0.7's correction to geometric was right.
#   - CORRECTED: the five partials of a mixture were weighted 1.00 / 0.88 /
#     0.76 by distance from the centre. Stockhausen specifies that the five
#     frequencies are recorded at equal level, so equal levels are now the
#     default (Equal partial levels, in Edit details). This changes the sound
#     slightly: mixtures are brighter at their extremes.
#   - FLAGGED, NOT CHANGED: the historical realisation used the reverberation
#     chamber's WET signal only, the direct sound being physically cut from
#     the tape head. Wet-only reverb is still off by default here.
#   - Score redrawn. Colour is not in the original and is used for exactly one
#     purpose: the five Tongemisch widths I-V, the parameter Stockhausen
#     serialised and the one hardest to read in monochrome, since width shows
#     only as box height on a log axis. Grid, boxes and lettering stay black.
#   - Upper system now bands the five sections and marks them with numerals;
#     the five-part form was previously invisible.
#   - The tape strip, formerly an uninformative picket fence, is now a real
#     dual ruler: centimetres of tape above, seconds below.
#   - Lower system now draws ONE envelope per mixture in dB, coloured by width
#     class. The previous single overlaid curve merged simultaneous mixtures
#     into one unreadable line.
#   - Added a fidelity strip separating what comes from the sources from what
#     is a modelling choice. The largest remaining divergence is that mixtures
#     are built on five fixed pitch registers rather than the historical
#     series of starting degrees; the new figure makes that visible as five
#     horizontal bands.
#
# Changelog v0.7:
#   - HISTORICAL CORRECTION: serial Tongemische again use equally spaced
#     scale indices (geometric spacing in Hz), not equal-Hz spacing.
#   - Score redesigned as a historically informed two-system monochrome layout,
#     preserving the 81 frequency lines and a separate articulation/amplitude
#     system rather than a generic modern data plot.
#   - Added tape-material time reference: 76.2 cm/s and 2.5 cm base unit.
#   - Compact main form; engineering/model controls moved to Edit details.
#   - Added random seed, output peak, validation, final peak/RMS QC.
#   - Fixed the exponential envelope so it closes smoothly at the event end.
#   - Score text strips use explicit viewports to avoid collisions.
# ============================================================

form Studie II Generator v0.7
    optionmenu Generation_mode 1
        option Random (creative, varied)
        option Serial (Studie II-inspired model)
    positive Duration_s 10.0

    boolean Edit_details 0
    boolean Draw_score 1
    boolean Play_result 1
endform

# === Advanced defaults ===
sample_rate_Hz = 44100
base_frequency_Hz = 100
min_amplitude = 0.10
max_amplitude = 0.30
random_groups = 7
rotation_offset = 0
wet_only_reverb = 0
equal_partial_levels = 1
output_peak = 0.95
random_seed = 0

if edit_details
    beginPause: "Studie II v0.7 - Model / Audio Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        positive: "Base frequency (Hz)", base_frequency_Hz
        positive: "Minimum event amplitude", min_amplitude
        positive: "Maximum event amplitude", max_amplitude
        integer: "Random-mode groups", random_groups
        integer: "Serial rotation offset", rotation_offset
        boolean: "Wet-only reverb model", wet_only_reverb
        boolean: "Equal partial levels (historical)", equal_partial_levels
        positive: "Output peak", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# === Validation ===
if duration_s < 0.20
    exitScript: "Duration must be at least 0.20 s."
endif
if sample_rate_Hz < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be positive."
endif
if min_amplitude <= 0 or max_amplitude <= 0 or min_amplitude > max_amplitude
    exitScript: "Amplitude range must be positive and Min <= Max."
endif
if random_groups < 1
    exitScript: "Random-mode groups must be at least 1."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in (0, 1]."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if random_seed = 0
    random_initializeSafelyAndUnpredictably()
else
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

num_groups = random_groups

# === Constants ===

uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
scaleRatio = 5 ^ (1 / 25)
tapeSpeed_cm_s = 76.2
baseTapeUnit_cm = 2.5
baseTimeUnit = baseTapeUnit_cm / tapeSpeed_cm_s

# === Build idealized 81-tone frequency scale ===
# Adjacent scale degrees have the constant ratio 5^(1/25).
for i to 81
    freq[i] = base_frequency_Hz * (scaleRatio ^ (i - 1))
endfor

nyquist_Hz = sample_rate_Hz / 2
safeNyquist_Hz = 0.95 * nyquist_Hz
if freq[81] >= safeNyquist_Hz
    exitScript: "The 81-tone scale reaches " + fixed$(freq[81], 1) + " Hz, above the safe Nyquist limit " + fixed$(safeNyquist_Hz, 1) + " Hz. Lower Base frequency or raise Sample rate."
endif

# === Info ===
writeInfoLine: "=== Stockhausen Studie II Generator ==="
if generation_mode = 1
    appendInfoLine: "Mode: Random (quasi-Studie II)"
else
    appendInfoLine: "Mode: Serial (Studie II-inspired; not a transcription)"
endif
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Frequency range: ", fixed$(freq[1], 1), " - ", fixed$(freq[81], 1), " Hz"
appendInfoLine: "Scale ratio: 5^(1/25) = ", fixed$(scaleRatio, 6)
appendInfoLine: "Tape reference: ", fixed$(tapeSpeed_cm_s, 1), " cm/s | base unit ", fixed$(baseTapeUnit_cm, 1), " cm = ", fixed$(baseTimeUnit * 1000, 2), " ms"
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
    
    # Compact five-class duration MODEL (not a transcription of the historical
    # 61-value duration table). The physical base unit is the historical 2.5 cm.
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
sectionNum = 0
subsectionNum = 0
groupNum = 0

# Pre-allocate arrays
for i to maxStoredEvents
    evStart[i] = 0
    evEnd[i] = 0
    evDur[i] = 0
    evAmp[i] = 0
    evEnv[i] = 0
    evWidth[i] = 0
    evSection[i] = 0
    evSub[i] = 0
    evGroup[i] = 0
    evRegister[i] = 0
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
timeScale = 1.0

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
    # Creative post-mix approximation of a wet-only reverberant treatment.
    # This is not a reconstruction of the historical chamber/tape process.
    # Modelled as a dense
    # cluster of attenuated, delayed copies of the dry signal (no dry kept).
    appendInfoLine: "Applying wet-only post-mix reverb model..."
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
    appendInfoLine: "Applying light post-mix reverb..."
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
Scale peak: output_peak

outputSound = selected("Sound")
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

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
    evWidth[numEvents] = .spreadFactor
    evSection[numEvents] = sectionNum
    evSub[numEvents] = subsectionNum
    evGroup[numEvents] = groupNum
    evRegister[numEvents] = 0
    
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
    
    # Five sine tones selected from the 81-tone scale at a constant INDEX
    # spacing of 1..5 degrees. Frequency spacing is therefore geometric in Hz.
    .startIndex = .centerIdx - 2 * .spreadFactor
    for .c to 5
        .ix = .startIndex + (.c - 1) * .spreadFactor
        .fc[.c] = freq[.ix]
    endfor
    
    # Get duration
    @getNextToken
    .durToken = getNextToken.value
    .duration = durMult[.durToken] * baseTimeUnit
    
    # Get amplitude
    @getNextToken
    .ampToken = getNextToken.value
    .amplitude = min_amplitude + (.ampToken - 1) / 4 * (max_amplitude - min_amplitude)
    
    # Historical realization used falling reverberant envelopes and their
    # tape-reversed rising counterparts. The five-valued token is therefore
    # mapped to two directions in Serial mode; Random mode retains five creative
    # envelope classes.
    @getNextToken
    .envToken = getNextToken.value
    if (.envToken mod 2) = 1
        .envType = 6
    else
        .envType = 7
    endif
    
    # Store event
    numEvents = numEvents + 1
    
    evStart[numEvents] = .startTime
    evEnd[numEvents] = .startTime + .duration
    evDur[numEvents] = .duration
    evAmp[numEvents] = .amplitude
    evEnv[numEvents] = .envType
    evWidth[numEvents] = .spreadFactor
    evSection[numEvents] = sectionNum
    evSub[numEvents] = subsectionNum
    evGroup[numEvents] = groupNum
    evRegister[numEvents] = .pitchToken
    
    for .c to 5
        evFreq[numEvents, .c] = .fc[.c]
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
        # Stockhausen specifies that the five frequencies of a mixture are
        # recorded at equal level ("the five frequencies are recorded at
        # 0 dB"). Earlier versions attenuated the outer partials to 0.76 of
        # the centre, which softened the mixture but contradicted the source.
        if equal_partial_levels
            .compAmp = .amplitude
        else
            .compAmp = .amplitude * (1.0 - abs(.comp - 3) * 0.12)
        endif
        
        .compAmp$ = fixed$(.compAmp, 5)
        .freq$ = fixed$(.frequency, 2)
        
        selectObject: .mixSound
        if .envType = 7
            Formula: "self + " + .compAmp$ + " * sin(twoPi * " + .freq$ + " * (x - " + fixed$(.duration, 6) + "))"
        else
            Formula: "self + " + .compAmp$ + " * sin(twoPi * " + .freq$ + " * x)"
        endif
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
        Formula: "self * exp(-x / " + fixed$(.tau, 6) + ")"
        .att3 = min(0.004, .duration * 0.08)
        .rel3 = min(0.012, .duration * 0.15)
        Fade in: 0, 0, .att3, "yes"
        Fade out: 0, .duration - .rel3, .rel3, "yes"
    elsif .envType = 4
        .peak = .duration / 2
        Formula: "self * (1 - abs(x - " + fixed$(.peak, 6) + ") / " + fixed$(.peak, 6) + ")"
    elsif .envType = 5
        .att5 = min(0.003, .duration * 0.08)
        .rel5 = min(0.006, .duration * 0.12)
        Fade in: 0, 0, .att5, "yes"
        Fade out: 0, .duration - .rel5, .rel5, "yes"
    elsif .envType = 6
        # Falling reverberant envelope (forward tape direction).
        Formula: "self * exp(-3 * x / " + fixed$(.duration, 6) + ") * (1 - x / " + fixed$(.duration, 6) + ")"
    else
        # Rising envelope: time-reversed counterpart of type 6.
        Formula: "self * exp(-3 * (" + fixed$(.duration, 6) + " - x) / " + fixed$(.duration, 6) + ") * (x / " + fixed$(.duration, 6) + ")"
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
# ==============================================================================
# Procedure: drawScore
#
# Two systems, as in the published score of 1954: an upper system plotting the
# frequency band of each Tongemisch against time, and a lower system plotting
# its amplitude envelope. Between them runs the tape ruler, because the score's
# own time unit is centimetres of tape at 76.2 cm/s.
#
# Colour is not in the original, which is ink on graph paper. It is used here
# for one thing only: the five Tongemisch WIDTHS (I-V = 1..5 scale steps). That
# is the parameter Stockhausen serialised and the one a monochrome print makes
# hardest to read, since width shows only as box height on a log axis. Grid,
# rules, boxes and lettering stay black so the page still reads as a score.
# ==============================================================================
procedure drawScore

    .lo = 1.32
    .hi = 7.72
    .ink$ = "{0.12,0.12,0.14}"
    .grid$ = "{0.86,0.86,0.88}"
    .grid5$ = "{0.72,0.72,0.75}"
    .faint$ = "{0.45,0.45,0.50}"
    .paper$ = "{0.995,0.993,0.985}"

    # Width classes I-V. Ordered dark-to-light so the narrowest mixture reads
    # as the most concentrated.
    .w1$ = "{0.16,0.24,0.48}"
    .w2$ = "{0.20,0.48,0.60}"
    .w3$ = "{0.32,0.55,0.35}"
    .w4$ = "{0.78,0.55,0.20}"
    .w5$ = "{0.66,0.24,0.26}"

    .logLo = ln(freq[1])
    .logHi = ln(freq[81])
    .span = .logHi - .logLo

    if duration_s <= 6
        .tTick = 1
    elsif duration_s <= 30
        .tTick = 2
    elsif duration_s <= 90
        .tTick = 10
    else
        .tTick = 30
    endif

    # Section spans, for the banding in the upper system.
    for .s to 5
        .secStart[.s] = -1
        .secEnd[.s] = -1
    endfor
    .haveSections = 0
    for .e to numEvents
        .s = evSection[.e]
        if .s >= 1 and .s <= 5
            .haveSections = 1
            if .secStart[.s] < 0 or evStart[.e] < .secStart[.s]
                .secStart[.s] = evStart[.e]
            endif
            if evEnd[.e] > .secEnd[.s]
                .secEnd[.s] = evEnd[.e]
            endif
        endif
    endfor

    for .w to 5
        .widthCount[.w] = 0
    endfor
    for .e to numEvents
        .w = evWidth[.e]
        if .w >= 1 and .w <= 5
            .widthCount[.w] = .widthCount[.w] + 1
        endif
    endfor

    Erase all
    Solid line
    Line width: 1

    # ======================= TITLE =======================
    Select inner viewport: 0.60, 7.72, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    if generation_mode = 2
        Text: 0.5, "centre", 0.80, "half", "##STUDIE II — SERIAL MODEL##"
    else
        Text: 0.5, "centre", 0.80, "half", "##STUDIE II — RANDOM MODE##"
    endif
    Font size: 6
    Colour: .faint$
    Text: 0.5, "centre", 0.44, "half",
        ... "81-tone scale on 5^(1/25), 100 Hz to 17.2 kHz  |  five-sine Tongemische  |  "
        ... + "tape ruler at 76.2 cm/s  |  " + string$(numEvents) + " mixtures"
    Font size: 5
    Text: 0.5, "centre", 0.12, "half",
        ... "a historically informed model, not a transcription; colour encodes Tongemisch width and is not in the original score"

    # ======================= UPPER SYSTEM =======================
    Select inner viewport: 0.60, 7.72, 0.86, 1.04
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##UPPER SYSTEM — Tongemische on the 81-tone scale##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "each box spans the five sine tones of one mixture; inner rules are the tones themselves"

    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Paint rectangle: .paper$, 0, duration_s, .logLo, .logHi

    # Section banding: the five-part form, invisible in the previous layout.
    if .haveSections
        Select inner viewport: .lo, .hi, 1.10, 3.62
        Axes: 0, duration_s, .logLo, .logHi
        for .s to 5
            if .secStart[.s] >= 0 and (.s mod 2) = 0
                Paint rectangle: "{0.955,0.955,0.972}",
                    ... .secStart[.s], min(duration_s, .secEnd[.s]), .logLo, .logHi
            endif
        endfor
    endif

    # The 81 scale degrees, every fifth one stronger: this is the score's
    # own ruled staff, and the reason the piece has no octaves.
    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Line width: 1
    for .i to 81
        .y = ln(freq[.i])
        if ((.i - 1) mod 5) = 0
            Colour: .grid5$
        else
            Colour: .grid$
        endif
        Draw line: 0, .y, duration_s, .y
    endfor

    # Mixture boxes.
    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    for .e to numEvents
        .t0 = evStart[.e]
        .t1 = min(duration_s, evEnd[.e])
        if .t1 > .t0
            .fLoE = ln(evFreq[.e, 1])
            .fHiE = ln(evFreq[.e, 5])
            .w = evWidth[.e]
            if .w = 1
                .col$ = .w1$
            elsif .w = 2
                .col$ = .w2$
            elsif .w = 3
                .col$ = .w3$
            elsif .w = 4
                .col$ = .w4$
            else
                .col$ = .w5$
            endif
            # Amplitude reads as tint, so a quiet mixture is a pale box.
            .k = 0.30 + 0.70 * min(1, evAmp[.e] / max(1e-9, max_amplitude))
            Paint rectangle: .col$, .t0, .t1, .fLoE, .fHiE
        endif
    endfor

    # The five sine tones inside each box, and the box outline, in ink.
    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Line width: 1
    Colour: .ink$
    for .e to numEvents
        .t0 = evStart[.e]
        .t1 = min(duration_s, evEnd[.e])
        if .t1 > .t0
            for .c to 5
                .y = ln(evFreq[.e, .c])
                Draw line: .t0, .y, .t1, .y
            endfor
            Draw rectangle: .t0, .t1, ln(evFreq[.e, 1]), ln(evFreq[.e, 5])
        endif
    endfor

    # Section numerals sit on the staff, as structural marks rather than a key.
    if .haveSections
        Select inner viewport: .lo, .hi, 1.10, 3.62
        Axes: 0, duration_s, .logLo, .logHi
        Font size: 7
        Colour: "{0.55,0.55,0.60}"
        for .s to 5
            if .secStart[.s] >= 0 and .secStart[.s] < duration_s
                if .s = 1
                    .num$ = "I"
                elsif .s = 2
                    .num$ = "II"
                elsif .s = 3
                    .num$ = "III"
                elsif .s = 4
                    .num$ = "IV"
                else
                    .num$ = "V"
                endif
                Text: .secStart[.s] + 0.12, "left", .logHi - 0.04 * .span, "half", .num$
            endif
        endfor
    endif

    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    # Label every tenth scale degree with its degree number and frequency:
    # the degree is the compositional unit, the hertz value the acoustic one.
    for .i from 1 to 81
        if ((.i - 1) mod 10) = 0
            .fv = freq[.i]
            if .fv >= 1000
                .lab$ = string$(.i - 1) + "  " + fixed$(.fv / 1000, 1) + "k"
            else
                .lab$ = string$(.i - 1) + "  " + fixed$(.fv, 0)
            endif
            One mark left: ln(.fv), "no", "yes", "no", .lab$
        endif
    endfor
    Font size: 6
    Text left: "yes", "degree / Hz"

    # ======================= TAPE RULER =======================
    Select inner viewport: .lo, .hi, 3.78, 4.02
    Axes: 0, duration_s, 0, 1
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration_s, 0, 1

    Select inner viewport: .lo, .hi, 3.78, 4.02
    Axes: 0, duration_s, 0, 1
    Colour: .ink$
    Line width: 1
    Draw inner box
    Font size: 5
    Colour: .faint$
    .cmTotal = duration_s * tapeSpeed_cm_s
    .cmTick = 100
    if .cmTotal > 3000
        .cmTick = 500
    elsif .cmTotal < 600
        .cmTick = 50
    endif
    .nCm = floor(.cmTotal / .cmTick)
    Colour: .ink$
    for .k from 0 to .nCm
        .tc = .k * .cmTick / tapeSpeed_cm_s
        if .tc <= duration_s
            Draw line: .tc, 0.52, .tc, 1
            Text: .tc, "centre", 0.30, "half", string$(.k * .cmTick)
        endif
    endfor
    Font size: 5
    Colour: .faint$
    Text: duration_s * 0.998, "right", 0.78, "half", "cm of tape"

    Select inner viewport: .lo, .hi, 3.78, 4.02
    Axes: 0, duration_s, 0, 1
    Font size: 5
    Colour: "Black"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"

    # ======================= LOWER SYSTEM =======================
    Select inner viewport: 0.60, 7.72, 4.42, 4.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##LOWER SYSTEM — amplitude envelopes##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "one envelope per mixture, in dB, coloured by its width class"

    .dbFloor = -40
    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    Paint rectangle: .paper$, 0, duration_s, .dbFloor, 2

    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    Colour: .grid$
    Line width: 1
    for .d from -40 to 0
        if (.d mod 10) = 0
            Draw line: 0, .d, duration_s, .d
        endif
    endfor

    # Each event as its own envelope, drawn as a filled shape in its width
    # colour. Separating them by event is what the previous single overlaid
    # curve could not do: there, overlapping mixtures merged into one line.
    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    for .e to numEvents
        .t0 = evStart[.e]
        .t1 = min(duration_s, evEnd[.e])
        .dur = evEnd[.e] - evStart[.e]
        if .t1 > .t0 and .dur > 0
            .w = evWidth[.e]
            if .w = 1
                .col$ = .w1$
            elsif .w = 2
                .col$ = .w2$
            elsif .w = 3
                .col$ = .w3$
            elsif .w = 4
                .col$ = .w4$
            else
                .col$ = .w5$
            endif
            .peakLin = evAmp[.e] / max(1e-9, max_amplitude)
            .nSeg = 24
            .prevT = .t0
            .prevD = .dbFloor
            for .k from 0 to .nSeg
                .u = .k / .nSeg
                .tt = evStart[.e] + .u * .dur
                if evEnv[.e] = 7
                    .g = exp(-3 * (1 - .u)) * .u
                else
                    .g = exp(-3 * .u) * (1 - .u)
                endif
                .lin = .peakLin * .g
                if .lin > 1e-4
                    .db = 20 * log10(.lin)
                else
                    .db = .dbFloor
                endif
                if .db < .dbFloor
                    .db = .dbFloor
                endif
                if .tt <= duration_s and .k > 0
                    Paint rectangle: .col$, .prevT, .tt, .dbFloor,
                        ... (.prevD + .db) / 2
                endif
                .prevT = .tt
                .prevD = .db
            endfor
        endif
    endfor

    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1, 10, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"

    # ======================= KEY =======================
    Select inner viewport: 0.60, 7.72, 6.36, 6.72
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "Black"
    Text: 0.0, "left", 0.80, "half", "##TONGEMISCH WIDTH##"
    Font size: 5
    Colour: .faint$
    Text: 0.0, "left", 0.30, "half",
        ... "constant within a group, changing from group to group"

    Select inner viewport: 2.60, 7.72, 6.36, 6.72
    Axes: 0, 5, 0, 1
    for .w to 5
        if .w = 1
            .col$ = .w1$
            .rn$ = "I"
        elsif .w = 2
            .col$ = .w2$
            .rn$ = "II"
        elsif .w = 3
            .col$ = .w3$
            .rn$ = "III"
        elsif .w = 4
            .col$ = .w4$
            .rn$ = "IV"
        else
            .col$ = .w5$
            .rn$ = "V"
        endif
        Paint rectangle: .col$, .w - 1 + 0.04, .w - 1 + 0.30, 0.42, 0.86
        Colour: .ink$
        Line width: 1
        Draw rectangle: .w - 1 + 0.04, .w - 1 + 0.30, 0.42, 0.86
        Font size: 6
        Colour: "Black"
        Text: .w - 1 + 0.36, "left", 0.64, "half",
            ... .rn$ + " = " + string$(.w) + " step"
        Font size: 5
        Colour: .faint$
        Text: .w - 1 + 0.36, "left", 0.22, "half",
            ... string$(.widthCount[.w]) + " mixtures"
    endfor

    # ======================= FIDELITY / QC =======================
    Select inner viewport: 0.60, 7.72, 6.94, 7.56
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Select inner viewport: 0.60, 7.72, 6.94, 7.56
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.25,0.25,0.25}"
    Text: 0.02, "left", 0.80, "half",
        ... "FROM THE SOURCES  |  81 degrees of 5^(1/25) from "
        ... + fixed$(freq[1], 0) + " to " + fixed$(freq[81], 0)
        ... + " Hz  |  5 sections x 5 subsections x 5 groups x 1-5 sounds  |  "
        ... + "five-sine mixtures spaced 1-5 scale degrees  |  equal partial levels"
    Text: 0.02, "left", 0.50, "half",
        ... "MODEL CHOICES  |  five fixed pitch registers, not the historical "
        ... + "starting-degree series  |  duration classes 1/2/4/8/16 base units, "
        ... + "not the score's cm table  |  envelopes idealised as decay and its reverse"
    Text: 0.02, "left", 0.20, "half",
        ... "OUTPUT  |  " + string$(numEvents) + " mixtures  |  span "
        ... + fixed$(duration_s, 2) + " s = " + fixed$(duration_s * tapeSpeed_cm_s, 0)
        ... + " cm of tape  |  peak " + fixed$(finalPeak, 3) + "  |  RMS "
        ... + fixed$(finalRMS, 4)

    Select inner viewport: 0.60, 7.72, 6.94, 7.56
    Axes: 0, 1, 0, 1
    Colour: "{0.52,0.52,0.54}"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
