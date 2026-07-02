# ============================================================
# Praat AudioTools - Percussive_Audio_Groove_Creator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Percussive Audio Groove Creator - detects bass drums, hi-hats,
#   and snares from audio using spectral classification, then
#   creates new groove patterns in various styles.
#
# Changelog v0.3:
#   - Visualization fix: three text panels (title, detection legend,
#     pattern-name caption) drew without setting their own Axes and so
#     inherited stale world coordinates from the preceding Draw (the
#     waveform's seconds axis / the grid's 0..totalSixteenths axis),
#     which bunched the legend labels at the far left and jammed the
#     caption against the left edge. Each now sets explicit Axes first.
#
# Changelog v0.2:
#   - Modern array syntax throughout
#   - Refactored beat pattern logic (no duplication)
#   - Added visualization
#   - Input validation
# ============================================================

form Percussive Groove Creator
    comment Select a Sound object first
    
    comment === Pattern ===
    optionmenu Pattern_length 3
        option 1 bar
        option 2 bars
        option 4 bars
    optionmenu Beat_pattern 1
        option Standard 4/4
        option Syncopated Funk
        option Breakbeat
        option Half-time Feel
        option Double-time Feel
        option Sparse Minimal
    real Tempo_BPM 120
    
    comment === Detection ===
    real Onset_threshold_dB -20
    positive Min_silence_s 0.05
    positive Max_segment_s 0.15
    
    comment === Groove ===
    real Groove_density 0.6
    positive Clip_max_length_s 0.12
    
    comment === Dynamics ===
    positive Attack_time_s 0.002
    positive Release_time_s 0.05
    real Shape_intensity 1.2
    
    comment === Output ===
    boolean Create_stereo 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

# === Get Sound Info ===
original = selected("Sound")
soundName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Info ===
writeInfoLine: "=== Percussive Groove Creator ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: ""

# === Convert to Mono ===
selectObject: original
if numChannels > 1
    Convert to mono
    soundMono = selected("Sound")
    appendInfoLine: "Converted to mono for analysis"
else
    Copy: "mono_temp"
    soundMono = selected("Sound")
endif

# === Create Intensity for Onset Detection ===
selectObject: soundMono
intensity = To Intensity: 70, 0, "yes"

selectObject: intensity
intensityMatrix = Down to Matrix

selectObject: intensityMatrix
numberOfFrames = Get number of columns
timeStep = Get column distance

# === Storage Arrays ===
maxEvents = 500
eventTime# = zero#(maxEvents)
eventType# = zero#(maxEvents)
eventSound# = zero#(maxEvents)
numberOfEvents = 0
lastEventTime = -1

# === Detect Percussive Onsets ===
appendInfoLine: "Detecting percussive events..."

for frame from 3 to numberOfFrames - 2
    selectObject: intensityMatrix
    time = Get x of column: frame
    
    if time > 0.02 and time < duration - 0.05
        if time - lastEventTime > min_silence_s
            currentValue = Get value in cell: 1, frame
            prevValue1 = Get value in cell: 1, frame - 1
            prevValue2 = Get value in cell: 1, frame - 2
            nextValue1 = Get value in cell: 1, frame + 1
            
            # Detect sharp peak (onset)
            if currentValue > prevValue1 and currentValue > prevValue2 and currentValue > nextValue1
                if currentValue > onset_threshold_dB
                    # Extract segment
                    segmentStart = max(0, time - 0.005)
                    segmentEnd = min(duration, time + max_segment_s)
                    
                    selectObject: soundMono
                    segment = Extract part: segmentStart, segmentEnd, "rectangular", 1, "no"
                    segDur = Get total duration
                    
                    if segDur > 0.015
                        # Analyze frequency content
                        spectrum = To Spectrum: "yes"
                        
                        lowEnergy = Get band energy: 20, 250
                        midEnergy = Get band energy: 250, 4000
                        highEnergy = Get band energy: 4000, 18000
                        
                        totalEnergy = lowEnergy + midEnergy + highEnergy
                        
                        # Classify based on spectral content
                        thisEventType = 0
                        if totalEnergy > 0
                            lowRatio = lowEnergy / totalEnergy
                            midRatio = midEnergy / totalEnergy
                            highRatio = highEnergy / totalEnergy
                            
                            # Bass drum: dominant low frequencies
                            if lowRatio > 0.55
                                thisEventType = 1
                            # Hi-hat: dominant high frequencies
                            elsif highRatio > 0.35
                                thisEventType = 2
                            # Snare: mid frequencies
                            elsif midRatio > 0.4
                                thisEventType = 3
                            endif
                        endif
                        
                        removeObject: spectrum
                        
                        if thisEventType > 0 and numberOfEvents < maxEvents
                            numberOfEvents += 1
                            eventTime#[numberOfEvents] = time
                            eventType#[numberOfEvents] = thisEventType
                            eventSound#[numberOfEvents] = segment
                            lastEventTime = time
                            
                            if thisEventType = 1
                                type$ = "BASS"
                            elsif thisEventType = 2
                                type$ = "HH"
                            else
                                type$ = "SNARE"
                            endif
                            
                            appendInfoLine: "  #", numberOfEvents, ": ", type$, " at ", fixed$(time, 3), "s"
                        else
                            removeObject: segment
                        endif
                    else
                        removeObject: segment
                    endif
                endif
            endif
        endif
    endif
endfor

removeObject: intensity, intensityMatrix

if numChannels > 1
    removeObject: soundMono
else
    removeObject: soundMono
endif

if numberOfEvents = 0
    exitScript: "No percussive events detected. Try lowering the onset threshold."
endif

appendInfoLine: ""
appendInfoLine: "Total detected: ", numberOfEvents, " events"

# === Organize by Type ===
maxPerType = 200
bassDrums# = zero#(maxPerType)
hiHats# = zero#(maxPerType)
snares# = zero#(maxPerType)
numBass = 0
numHH = 0
numSnare = 0

for i to numberOfEvents
    if eventType#[i] = 1
        numBass += 1
        if numBass <= maxPerType
            bassDrums#[numBass] = eventSound#[i]
        endif
    elsif eventType#[i] = 2
        numHH += 1
        if numHH <= maxPerType
            hiHats#[numHH] = eventSound#[i]
        endif
    elsif eventType#[i] = 3
        numSnare += 1
        if numSnare <= maxPerType
            snares#[numSnare] = eventSound#[i]
        endif
    endif
endfor

appendInfoLine: "  → Bass drums: ", numBass
appendInfoLine: "  → Hi-hats: ", numHH
appendInfoLine: "  → Snares: ", numSnare
appendInfoLine: ""

if numBass = 0 and numHH = 0 and numSnare = 0
    exitScript: "No usable percussion detected."
endif

if numBass = 0 or numHH = 0 or numSnare = 0
    appendInfoLine: "WARNING: Not all types detected."
    appendInfoLine: "Pattern will use available types only."
    appendInfoLine: ""
endif

# === Calculate Pattern Parameters ===
if pattern_length = 1
    bars = 1
elsif pattern_length = 2
    bars = 2
else
    bars = 4
endif

beatDuration = 60.0 / tempo_BPM
patternDuration = bars * 4 * beatDuration
sixteenthDur = beatDuration / 4
totalSixteenths = bars * 4 * 4

appendInfoLine: "Creating ", bars, "-bar groove at ", tempo_BPM, " BPM..."
appendInfoLine: "Pattern duration: ", fixed$(patternDuration, 2), " s"
appendInfoLine: ""

# === Store Pattern for Visualization ===
patternHits# = zero#(totalSixteenths)
patternTypes# = zero#(totalSixteenths)

# === Procedure: Get Hit Type for Position ===
procedure getHitType: .beat, .sixteenth, .pattern, .density
    .result = 0
    .probability = randomUniform(0, 1)
    .beatMod4 = (.beat - 1) mod 4
    .beatMod8 = (.beat - 1) mod 8
    
    if .pattern = 1
        # Standard 4/4
        if .beatMod4 = 0 and .sixteenth = 1
            .result = 1
        elsif .beatMod4 = 2 and .sixteenth = 1
            if .probability < .density
                .result = 1
            endif
        elsif (.beatMod4 = 1 or .beatMod4 = 3) and .sixteenth = 1
            if .probability < .density + 0.2
                .result = 3
            endif
        elsif .sixteenth = 1 or .sixteenth = 3
            if .probability < .density * 0.8
                .result = 2
            endif
        elsif .probability < .density * 0.3
            .result = 2
        endif
        
    elsif .pattern = 2
        # Syncopated Funk
        if .beatMod4 = 0 and .sixteenth = 1
            .result = 1
        elsif .beatMod4 = 1 and .sixteenth = 4
            if .probability < .density
                .result = 1
            endif
        elsif .beatMod4 = 2 and .sixteenth = 3
            if .probability < .density
                .result = 1
            endif
        elsif (.beatMod4 = 1 or .beatMod4 = 3) and .sixteenth = 1
            if .probability < .density + 0.2
                .result = 3
            endif
        elsif .probability < .density * 0.9
            .result = 2
        endif
        
    elsif .pattern = 3
        # Breakbeat
        if .beatMod4 = 0 and .sixteenth = 1
            .result = 1
        elsif .beatMod4 = 0 and .sixteenth = 3
            if .probability < .density * 0.6
                .result = 1
            endif
        elsif .beatMod4 = 2 and (.sixteenth = 1 or .sixteenth = 4)
            if .probability < .density
                .result = 1
            endif
        elsif .beatMod4 = 1 and .sixteenth = 1
            .result = 3
        elsif .beatMod4 = 3 and (.sixteenth = 1 or .sixteenth = 3)
            if .probability < .density
                .result = 3
            endif
        elsif .probability < .density * 0.7
            .result = 2
        endif
        
    elsif .pattern = 4
        # Half-time Feel
        if .beatMod8 = 0 and .sixteenth = 1
            .result = 1
        elsif .beatMod8 = 4 and .sixteenth = 1
            if .probability < .density
                .result = 3
            endif
        elsif .sixteenth = 1
            if .probability < .density * 0.6
                .result = 2
            endif
        endif
        
    elsif .pattern = 5
        # Double-time Feel
        if .sixteenth = 1 or .sixteenth = 3
            if .probability < .density
                .result = 1
            endif
        elsif .sixteenth = 2 or .sixteenth = 4
            if .probability < .density * 0.8
                .result = 3
            endif
        elsif .probability < .density
            .result = 2
        endif
        
    elsif .pattern = 6
        # Sparse Minimal
        if .beatMod4 = 0 and .sixteenth = 1
            .result = 1
        elsif .beatMod4 = 2 and .sixteenth = 1
            if .probability < 0.3
                .result = 1
            endif
        elsif .beatMod4 = 1 and .sixteenth = 1
            if .probability < .density * 0.5
                .result = 3
            endif
        elsif (.beat - 1) mod 2 = 0 and .sixteenth = 1
            if .probability < .density * 0.4
                .result = 2
            endif
        endif
    endif
endproc

# === Procedure: Place Hit in Pattern ===
procedure placeHit: .patternID, .position, .soundID, .sampleRate, .clipMax, .attack, .release, .shape, .patternDur
    selectObject: .soundID
    .tempSound = Copy: "temp_hit"
    .soundDur = Get total duration
    
    # Clip if too long
    if .soundDur > .clipMax
        selectObject: .tempSound
        Extract part: 0, .clipMax, "rectangular", 1, "no"
        .shortened = selected("Sound")
        removeObject: .tempSound
        .tempSound = .shortened
        .soundDur = .clipMax
    endif
    
    # Create envelope
    selectObject: .tempSound
    .envFormula$ = "if x < .attack then (x/.attack)^(1/.shape) else if x > .soundDur - .release then ((.soundDur - x)/.release)^.shape else 1 fi fi"
    
    .envelope = Create Sound from formula: "env", 1, 0, .soundDur, .sampleRate, .envFormula$
    
    selectObject: .tempSound
    Formula: "self * object[.envelope]"
    removeObject: .envelope
    
    # Random velocity
    Scale peak: 0.7
    .velocity = 0.6 + randomUniform(0, 0.4)
    Formula: "self * .velocity"
    
    # Check bounds
    .maxLen = .patternDur - .position
    if .maxLen <= 0
        removeObject: .tempSound
    else
        if .soundDur > .maxLen
            selectObject: .tempSound
            Extract part: 0, .maxLen, "rectangular", 1, "no"
            .trimmed = selected("Sound")
            removeObject: .tempSound
            .tempSound = .trimmed
            .soundDur = .maxLen
        endif
        
        # Convert to matrix for fast placement
        selectObject: .tempSound
        .soundMatrix = Down to Matrix
        .nCols = Get number of columns
        
        # Add to pattern
        selectObject: .patternID
        .positionSamples = round(.position * .sampleRate)
        
        Formula: "if col >= .positionSamples + 1 and col <= .positionSamples + .nCols then self + object[.soundMatrix, 1, col - .positionSamples] else self fi"
        
        removeObject: .soundMatrix, .tempSound
    endif
endproc

# === Generate Left/Mono Pattern ===
pattern_left = Create Sound from formula: "pattern_L", 1, 0, patternDuration, sampleRate, "0"

bassIdx = 1
hhIdx = 1
snareIdx = 1
hitsPlacedL = 0
sixteenthIdx = 0

for beat from 1 to bars * 4
    beatStart = (beat - 1) * beatDuration
    
    for sixteenth from 1 to 4
        sixteenthIdx += 1
        position = beatStart + (sixteenth - 1) * sixteenthDur
        
        @getHitType: beat, sixteenth, beat_pattern, groove_density
        placeType = getHitType.result
        
        # Store for visualization
        patternTypes#[sixteenthIdx] = placeType
        
        if placeType > 0
            soundToUse = 0
            
            if placeType = 1 and numBass > 0
                soundToUse = bassDrums#[bassIdx]
                bassIdx = (bassIdx mod numBass) + 1
            elsif placeType = 2 and numHH > 0
                soundToUse = hiHats#[hhIdx]
                hhIdx = (hhIdx mod numHH) + 1
            elsif placeType = 3 and numSnare > 0
                soundToUse = snares#[snareIdx]
                snareIdx = (snareIdx mod numSnare) + 1
            endif
            
            if soundToUse > 0
                hitsPlacedL += 1
                patternHits#[sixteenthIdx] = 1
                @placeHit: pattern_left, position, soundToUse, sampleRate, clip_max_length_s, attack_time_s, release_time_s, shape_intensity, patternDuration
            endif
        endif
    endfor
endfor

appendInfoLine: "Left channel: ", hitsPlacedL, " hits placed"

# === Generate Right Channel (if stereo) ===
if create_stereo
    pattern_right = Create Sound from formula: "pattern_R", 1, 0, patternDuration, sampleRate, "0"
    
    bassIdx = 1
    hhIdx = 1
    snareIdx = 1
    hitsPlacedR = 0
    
    for beat from 1 to bars * 4
        beatStart = (beat - 1) * beatDuration
        
        for sixteenth from 1 to 4
            position = beatStart + (sixteenth - 1) * sixteenthDur
            
            # Get new random hit type (independent from L)
            @getHitType: beat, sixteenth, beat_pattern, groove_density
            placeType = getHitType.result
            
            if placeType > 0
                soundToUse = 0
                
                if placeType = 1 and numBass > 0
                    soundToUse = bassDrums#[bassIdx]
                    bassIdx = (bassIdx mod numBass) + 1
                elsif placeType = 2 and numHH > 0
                    soundToUse = hiHats#[hhIdx]
                    hhIdx = (hhIdx mod numHH) + 1
                elsif placeType = 3 and numSnare > 0
                    soundToUse = snares#[snareIdx]
                    snareIdx = (snareIdx mod numSnare) + 1
                endif
                
                if soundToUse > 0
                    hitsPlacedR += 1
                    @placeHit: pattern_right, position, soundToUse, sampleRate, clip_max_length_s, attack_time_s, release_time_s, shape_intensity, patternDuration
                endif
            endif
        endfor
    endfor
    
    appendInfoLine: "Right channel: ", hitsPlacedR, " hits placed"
    
    # Combine to stereo
    selectObject: pattern_left, pattern_right
    result = Combine to stereo
    removeObject: pattern_left, pattern_right
else
    result = pattern_left
endif

# === Finalize ===
selectObject: result
Scale peak: 0.95
if create_stereo
    Rename: soundName$ + "_groove_" + string$(bars) + "bar_stereo"
else
    Rename: soundName$ + "_groove_" + string$(bars) + "bar"
endif

# === Cleanup Detected Sounds ===
for i to numberOfEvents
    if eventSound#[i] > 0
        removeObject: eventSound#[i]
    endif
endfor

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 2, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.5, "half", "Percussive Groove: " + soundName$ + " (" + string$(bars) + " bar, " + string$(tempo_BPM) + " BPM)"
    
    # Original waveform with detected events
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark detected events
    for i to numberOfEvents
        t = eventTime#[i]
        eType = eventType#[i]
        
        if eType = 1
            Colour: "{0.8, 0.2, 0.2}"
        elsif eType = 2
            Colour: "{0.2, 0.7, 0.2}"
        else
            Colour: "{0.2, 0.2, 0.8}"
        endif
        
        Draw line: t, -0.8, t, 0.8
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Legend for detection
    Font size: 6
    # Explicit axes: the waveform Draw above left the x-axis in SECONDS, which
    # would bunch these fractional-position labels at the far left. Restore a
    # 0..1 fractional x-axis (y spans the waveform amplitude + headroom).
    Axes: 0, 1, -1, 1.2
    Colour: "{0.8, 0.2, 0.2}"
    Text: 0.15, "left", 1.1, "half", "Bass (" + string$(numBass) + ")"
    Colour: "{0.2, 0.7, 0.2}"
    Text: 0.4, "left", 1.1, "half", "HH (" + string$(numHH) + ")"
    Colour: "{0.2, 0.2, 0.8}"
    Text: 0.65, "left", 1.1, "half", "Snare (" + string$(numSnare) + ")"
    
    # Generated pattern waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Pattern"
    Text bottom: "yes", "Time (s)"
    
    # Pattern grid visualization
    Select outer viewport: 0, 8, 3.6, 5.2
    Select inner viewport: 0.6, 7.6, 3.8, 5.1
    
    Axes: 0, totalSixteenths, 0, 4
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, totalSixteenths, 0, 4
    
    # Draw beat lines
    Colour: "{0.8, 0.8, 0.8}"
    for b to bars * 4
        bPos = (b - 1) * 4
        if (b - 1) mod 4 = 0
            Colour: "{0.5, 0.5, 0.5}"
            Line width: 2
        else
            Colour: "{0.8, 0.8, 0.8}"
            Line width: 1
        endif
        Draw line: bPos, 0, bPos, 4
    endfor
    Line width: 1
    
    # Draw hits
    for s to totalSixteenths
        hitType = patternTypes#[s]
        if hitType > 0
            xPos = s - 0.5
            
            if hitType = 1
                yPos = 3
                dotColor$ = "{0.8, 0.2, 0.2}"
            elsif hitType = 2
                yPos = 2
                dotColor$ = "{0.2, 0.7, 0.2}"
            else
                yPos = 1
                dotColor$ = "{0.2, 0.2, 0.8}"
            endif
            
            Paint circle (mm): dotColor$, xPos, yPos, 1.5
        endif
    endfor
    
    # Labels
    Colour: "Black"
    Draw inner box
    Font size: 7
    
    Axes: 0, totalSixteenths, 0, 4
    Colour: "{0.8, 0.2, 0.2}"
    Text: -0.5, "right", 3, "half", "Bass"
    Colour: "{0.2, 0.7, 0.2}"
    Text: -0.5, "right", 2, "half", "HH"
    Colour: "{0.2, 0.2, 0.8}"
    Text: -0.5, "right", 1, "half", "Snare"
    
    Colour: "Black"
    Text bottom: "yes", "16th notes"
    
    # Pattern name
    Select outer viewport: 1, 8, 5.3, 5.6
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    if beat_pattern = 1
        patternName$ = "Standard 4/4"
    elsif beat_pattern = 2
        patternName$ = "Syncopated Funk"
    elsif beat_pattern = 3
        patternName$ = "Breakbeat"
    elsif beat_pattern = 4
        patternName$ = "Half-time"
    elsif beat_pattern = 5
        patternName$ = "Double-time"
    else
        patternName$ = "Sparse Minimal"
    endif
    
    # Explicit axes: without this the caption inherits the grid axis
    # (0..totalSixteenths) above, jamming x=1.5 against the left edge.
    Axes: 0, 3, 0, 1
    Text: 1.5, "centre", 0.5, "half", "Pattern: " + patternName$ + " | Density: " + fixed$(groove_density, 2) + " | Hits: " + string$(hitsPlacedL) + if create_stereo then "/" + string$(hitsPlacedR) else "" fi
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result