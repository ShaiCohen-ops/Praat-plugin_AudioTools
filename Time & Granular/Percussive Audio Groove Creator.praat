# ============================================================
# Praat AudioTools - Percussive_Audio_Groove_Creator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Percussive Audio Groove Creator - detects bass drums, hi-hats,
#   and snares from audio using spectral classification, then
#   creates new groove patterns in various styles.
#
# Changelog v0.5.1:
#   - FIX: Onset_threshold_dB is now interpreted as a relative dB offset
#     below the maximum Intensity of the current analysis file. The previous
#     code compared the default -20 directly with Praat Intensity values in
#     dB SPL, so the threshold was effectively inactive for normal digital audio.
#   - The effective threshold is now:
#         maxIntensity_dB + Onset_threshold_dB
#     Thus -20 means 20 dB below the file's maximum Intensity.
#   - Positive threshold offsets are rejected; the Info window reports the
#     measured maximum Intensity and the resulting effective onset threshold.
#
# Changelog v0.5:
#   - VISUALIZATION ONLY: rebuilt to the AudioTools library standard.
#   - Added an explicit process panel: onset detection -> spectral class ->
#     sample pools -> groove rule -> clip placement/envelope.
#   - Stereo groove grid now shows the actual independently generated L and R
#     patterns; v0.4 showed only the left-channel pattern.
#   - Grid dots now represent hits that were actually rendered, so a requested
#     class with no available detected sample is not shown as an audible hit.
#   - Detection colours normalized to the library palette and kept semantic:
#     red = Bass, green = HH, blue = Snare. Source/output waveforms are neutral.
#   - Source visualization now shows the same zero-based mono signal used by the
#     detector, and source/output use a shared amplitude scale.
#   - Title/subtitle, panel greys, fonts, summary strip and viewports aligned to
#     the library standard; Sound names with underscores are escaped.
#   - FIX: visualization ends by re-selecting the full page so PNG/EPS/clipboard
#     export captures the whole figure instead of only the final caption strip.
#
# Changelog v0.4:
#   - API COMPATIBILITY: the complete public form is unchanged from v0.3
#     (same parameter names, order, types, defaults, and output naming).
#   - FIX: analysis now uses a zero-based mono copy, so non-zero Sound start
#     times no longer break onset bounds or segment extraction.
#   - FIX: spectral classification respects Nyquist. High/mid band queries
#     are skipped when the sample rate cannot represent those bands.
#   - FIX: per-type event arrays can hold all maxEvents. v0.3 counted beyond
#     the 200-entry arrays and could later index empty/out-of-range entries.
#   - FIX: Half-time now places the backbeat on beat 3 of each bar, instead
#     of beat 5 of an 8-beat cycle (which produced no snare in a 1-bar form).
#   - FIX: Double-time and Sparse-Minimal hi-hat branches are reachable.
#   - HARDENING: validates tempo/density/shape, clamps envelope attack/release
#     against each hit duration, and avoids Scale peak on silent hit/output.
#   - VIS: detected-event markers remain aligned when the original Sound has
#     a non-zero start time.
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
sourceStart = Get start time
sourceEnd = Get end time
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Internal guards only; public parameters are unchanged.
if tempo_BPM <= 0
    exitScript: "Tempo BPM must be > 0"
endif
if groove_density < 0 or groove_density > 1
    exitScript: "Groove density must be between 0 and 1"
endif
if shape_intensity <= 0
    exitScript: "Shape intensity must be > 0"
endif
if onset_threshold_dB > 0
    exitScript: "Onset_threshold_dB must be <= 0 because it is a dB offset below the file maximum (for example -20)."
endif

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

selectObject: soundMono
Shift times to: "start time", 0

# === Create Intensity for Onset Detection ===
selectObject: soundMono
intensity = To Intensity: 70, 0, "yes"

selectObject: intensity
maxIntensity_dB = Get maximum: 0, 0, "Parabolic"
if maxIntensity_dB = undefined
    exitScript: "Could not determine a maximum Intensity for onset detection."
endif
effectiveOnsetThreshold_dB = maxIntensity_dB + onset_threshold_dB
appendInfoLine: "Onset threshold: ", fixed$(onset_threshold_dB, 1),
    ... " dB below file maximum (max ", fixed$(maxIntensity_dB, 1),
    ... " dB; effective ", fixed$(effectiveOnsetThreshold_dB, 1), " dB)"
appendInfoLine: ""

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
                if currentValue > effectiveOnsetThreshold_dB
                    # Extract segment
                    segmentStart = max(0, time - 0.005)
                    segmentEnd = min(duration, time + max_segment_s)
                    
                    selectObject: soundMono
                    segment = Extract part: segmentStart, segmentEnd, "rectangular", 1, "no"
                    segDur = Get total duration
                    
                    if segDur > 0.015
                        # Analyze frequency content
                        spectrum = To Spectrum: "yes"
                        
                        # Query only frequency regions that exist below Nyquist.
                        lowEnergy = 0
                        midEnergy = 0
                        highEnergy = 0
                        if nyquist > 20
                            lowTop = min(250, nyquist)
                            if lowTop > 20
                                lowEnergy = Get band energy: 20, lowTop
                            endif
                        endif
                        if nyquist > 250
                            midTop = min(4000, nyquist)
                            if midTop > 250
                                midEnergy = Get band energy: 250, midTop
                            endif
                        endif
                        if nyquist > 4000
                            highTop = min(18000, nyquist)
                            if highTop > 4000
                                highEnergy = Get band energy: 4000, highTop
                            endif
                        endif
                        
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

removeObject: soundMono

if numberOfEvents = 0
    exitScript: "No percussive events detected. Try lowering the onset threshold."
endif

appendInfoLine: ""
appendInfoLine: "Total detected: ", numberOfEvents, " events"

# === Organize by Type ===
maxPerType = maxEvents
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
if patternDuration < 2 / sampleRate
    exitScript: "Tempo is too high for this sample rate and pattern length"
endif

appendInfoLine: "Creating ", bars, "-bar groove at ", tempo_BPM, " BPM..."
appendInfoLine: "Pattern duration: ", fixed$(patternDuration, 2), " s"
appendInfoLine: ""

# === Store Pattern for Visualization ===
patternHits# = zero#(totalSixteenths)
patternTypes# = zero#(totalSixteenths)
patternHitsR# = zero#(totalSixteenths)
patternTypesR# = zero#(totalSixteenths)

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
        # Half-time Feel: kick on beat 1, backbeat on beat 3 of each bar.
        if .beatMod4 = 0 and .sixteenth = 1
            .result = 1
        elsif .beatMod4 = 2 and .sixteenth = 1
            if .probability < .density
                .result = 3
            endif
        elsif .sixteenth = 1 or .sixteenth = 3
            if .probability < .density * 0.6
                .result = 2
            endif
        endif
        
    elsif .pattern = 5
        # Double-time Feel. If the main kick/snare does not fire, allow the
        # same sixteenth position to fall back to a hi-hat.
        if .sixteenth = 1 or .sixteenth = 3
            if .probability < .density
                .result = 1
            elsif randomUniform(0, 1) < .density * 0.8
                .result = 2
            endif
        else
            if .probability < .density * 0.8
                .result = 3
            elsif randomUniform(0, 1) < .density * 0.8
                .result = 2
            endif
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
        elsif .sixteenth = 3
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
    
    # Create envelope. Keep attack and release from overlapping pathologically
    # on very short clips; public attack/release parameters are unchanged.
    .attackUsed = min(.attack, .soundDur * 0.45)
    .releaseUsed = min(.release, .soundDur * 0.45)
    selectObject: .tempSound
    .envFormula$ = "if x < " + fixed$(.attackUsed, 12) + " then (x/" + fixed$(.attackUsed, 12) + ")^(1/" + fixed$(.shape, 12) + ") else if x > " + fixed$(.soundDur - .releaseUsed, 12) + " then ((" + fixed$(.soundDur, 12) + " - x)/" + fixed$(.releaseUsed, 12) + ")^" + fixed$(.shape, 12) + " else 1 fi fi"
    .envelope = Create Sound from formula: "env", 1, 0, .soundDur, .sampleRate, .envFormula$
    
    selectObject: .tempSound
    Formula: "self * object[.envelope]"
    removeObject: .envelope
    
    # Random velocity. Do not try to normalize an all-zero hit.
    .hitPeak = Get absolute extremum: 0, 0, "Sinc70"
    if .hitPeak > 0
        Scale peak: 0.7
    endif
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

hitsPlacedR = 0
# === Generate Right Channel (if stereo) ===
if create_stereo
    pattern_right = Create Sound from formula: "pattern_R", 1, 0, patternDuration, sampleRate, "0"
    
    bassIdx = 1
    hhIdx = 1
    snareIdx = 1
    hitsPlacedR = 0
    sixteenthIdxR = 0
    
    for beat from 1 to bars * 4
        beatStart = (beat - 1) * beatDuration
        
        for sixteenth from 1 to 4
            sixteenthIdxR += 1
            position = beatStart + (sixteenth - 1) * sixteenthDur
            
            # Get new random hit type (independent from L)
            @getHitType: beat, sixteenth, beat_pattern, groove_density
            placeType = getHitType.result
            patternTypesR#[sixteenthIdxR] = placeType
            
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
                    patternHitsR#[sixteenthIdxR] = 1
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
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: 0.95
else
    appendInfoLine: "WARNING: Groove pattern rendered silence (detected types did not match generated hits)."
endif
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
    Plain line
    Black

    # Pattern name is useful in title, process panel and summary.
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

    # Escape underscores so Praat does not typeset them as subscripts.
    vizName$ = replace$(soundName$, "_", "\_ ", 0)

    # Show exactly the mono, zero-based signal used by onset/class analysis.
    selectObject: original
    if numChannels > 1
        vizSource = Convert to mono
    else
        vizSource = Copy: "groove_viz_source"
    endif
    selectObject: vizSource
    Shift times to: "start time", 0
    sourcePeak = Get absolute extremum: 0, 0, "None"

    selectObject: result
    outputPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(sourcePeak, outputPeak)
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.12

    if create_stereo
        hitSummary$ = string$(hitsPlacedL) + " L / " + string$(hitsPlacedR) + " R hits"
        channelMode$ = "stereo; independent L/R patterns"
    else
        hitSummary$ = string$(hitsPlacedL) + " hits"
        channelMode$ = "mono pattern"
    endif

    # ----------------------------------------------------------
    # TITLE + SUBTITLE — library standard
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Percussive Audio Groove Creator v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$ + " | " + patternName$
        ... + " | " + string$(bars) + " bar | " + fixed$(tempo_BPM, 0) + " BPM"
        ... + " | density " + fixed$(groove_density, 2) + " | " + hitSummary$

    # ----------------------------------------------------------
    # DETECTED SAMPLE POOLS — colour is reserved for event class
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.55, 0.76
    Select inner viewport: 0.60, 7.70, 0.56, 0.75
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.00, "left", 0.5, "half", "Detected pools:"
    Colour: "{0.78, 0.28, 0.22}"
    Text: 0.18, "left", 0.5, "half", "Bass (" + string$(numBass) + ")"
    Colour: "{0.35, 0.60, 0.40}"
    Text: 0.42, "left", 0.5, "half", "HH (" + string$(numHH) + ")"
    Colour: "{0.25, 0.45, 0.75}"
    Text: 0.62, "left", 0.5, "half", "Snare (" + string$(numSnare) + ")"
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.82, "left", 0.5, "half", "markers = detected onsets"

    # ----------------------------------------------------------
    # SOURCE USED BY DETECTOR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.80, 2.03
    Select inner viewport: 0.60, 7.70, 0.91, 1.91
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0
    selectObject: vizSource
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"

    # Event markers use zero-based eventTime#, matching the analysis signal.
    for i to numberOfEvents
        if eventType#[i] = 1
            Colour: "{0.78, 0.28, 0.22}"
        elsif eventType#[i] = 2
            Colour: "{0.35, 0.60, 0.40}"
        else
            Colour: "{0.25, 0.45, 0.75}"
        endif
        Line width: 1.2
        Draw line: eventTime#[i], -sharedAmp, eventTime#[i], sharedAmp
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Analysis source"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PROCESS EXPLANATION — not a scientific block diagram; a user map
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.15, 3.24
    Select inner viewport: 0.60, 7.70, 2.26, 3.12
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "How the source becomes a groove"

    # Five compact stages.
    stageLeft[1] = 0.025
    stageRight[1] = 0.185
    stageLeft[2] = 0.220
    stageRight[2] = 0.380
    stageLeft[3] = 0.415
    stageRight[3] = 0.575
    stageLeft[4] = 0.610
    stageRight[4] = 0.770
    stageLeft[5] = 0.805
    stageRight[5] = 0.975
    for st to 5
        Paint rectangle: "{0.94, 0.94, 0.94}", stageLeft[st], stageRight[st], 0.20, 0.82
        Colour: "{0.70, 0.70, 0.74}"
        Draw rectangle: stageLeft[st], stageRight[st], 0.20, 0.82
    endfor
    Colour: "{0.35, 0.35, 0.50}"
    Line width: 1.2
    for st to 4
        x1 = stageRight[st]
        x2 = stageLeft[st + 1]
        Draw line: x1, 0.51, x2, 0.51
        Font size: 7
        Text: (x1 + x2) / 2, "centre", 0.51, "half", ">"
    endfor
    Line width: 1

    Font size: 7
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.105, "centre", 0.64, "half", "##1  Detect##"
    Font size: 6
    Text: 0.105, "centre", 0.39, "half", "sharp intensity peaks"
    Font size: 7
    Text: 0.300, "centre", 0.64, "half", "##2  Classify##"
    Font size: 6
    Text: 0.300, "centre", 0.39, "half", "low / mid / high energy"
    Font size: 7
    Text: 0.495, "centre", 0.64, "half", "##3  Build pools##"
    Font size: 6
    Colour: "{0.78, 0.28, 0.22}"
    Text: 0.455, "centre", 0.39, "half", "Bass"
    Colour: "{0.35, 0.60, 0.40}"
    Text: 0.495, "centre", 0.39, "half", "HH"
    Colour: "{0.25, 0.45, 0.75}"
    Text: 0.535, "centre", 0.39, "half", "Snare"
    Font size: 7
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.690, "centre", 0.64, "half", "##4  Choose grid##"
    Font size: 6
    Text: 0.690, "centre", 0.39, "half", patternName$ + ", density " + fixed$(groove_density, 2)
    Font size: 7
    Text: 0.890, "centre", 0.64, "half", "##5  Place hits##"
    Font size: 6
    Text: 0.890, "centre", 0.39, "half", "clip + envelope + velocity"

    # ----------------------------------------------------------
    # GENERATED GROOVE WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.36, 4.58
    Select inner viewport: 0.60, 7.70, 3.47, 4.46
    Axes: 0, patternDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, patternDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, patternDuration, 0
    selectObject: result
    Colour: "{0.35, 0.35, 0.50}"
    Line width: 1
    Draw: 0, patternDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Generated groove"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # ACTUAL GROOVE GRID — stereo shows both independent patterns
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.72, 6.82
    Select inner viewport: 0.60, 7.70, 4.86, 6.67

    if create_stereo
        gridTop = 6
    else
        gridTop = 4
    endif
    Axes: 0, totalSixteenths, 0, gridTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalSixteenths, 0, gridTop

    # Beat and bar guides.
    for b to bars * 4
        bPos = (b - 1) * 4
        if (b - 1) mod 4 = 0
            Colour: "{0.65, 0.65, 0.68}"
            Line width: 1.5
        else
            Colour: "{0.85, 0.85, 0.87}"
            Line width: 1
        endif
        Draw line: bPos, 0, bPos, gridTop
    endfor
    Line width: 1

    if create_stereo
        Colour: "{0.82, 0.82, 0.84}"
        Draw line: 0, 3, totalSixteenths, 3
    endif

    # Left/mono actual rendered hits.
    for s to totalSixteenths
        if patternHits#[s] = 1
            hitType = patternTypes#[s]
            xPos = s - 0.5
            if create_stereo
                if hitType = 1
                    yPos = 5.5
                elsif hitType = 2
                    yPos = 4.5
                else
                    yPos = 3.5
                endif
            else
                if hitType = 1
                    yPos = 3
                elsif hitType = 2
                    yPos = 2
                else
                    yPos = 1
                endif
            endif
            if hitType = 1
                dotColor$ = "{0.78, 0.28, 0.22}"
            elsif hitType = 2
                dotColor$ = "{0.35, 0.60, 0.40}"
            else
                dotColor$ = "{0.25, 0.45, 0.75}"
            endif
            Paint circle (mm): dotColor$, xPos, yPos, 1.55
        endif
    endfor

    # Right-channel actual rendered hits.
    if create_stereo
        for s to totalSixteenths
            if patternHitsR#[s] = 1
                hitType = patternTypesR#[s]
                xPos = s - 0.5
                if hitType = 1
                    yPos = 2.5
                    dotColor$ = "{0.78, 0.28, 0.22}"
                elsif hitType = 2
                    yPos = 1.5
                    dotColor$ = "{0.35, 0.60, 0.40}"
                else
                    yPos = 0.5
                    dotColor$ = "{0.25, 0.45, 0.75}"
                endif
                Paint circle (mm): dotColor$, xPos, yPos, 1.55
            endif
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    if create_stereo
        Text top: "no", "Actual groove grid – colour = source class; upper group = L, lower group = R"
        Font size: 6
        Colour: "{0.78, 0.28, 0.22}"
        Text: -0.35, "right", 5.5, "half", "L Bass"
        Colour: "{0.35, 0.60, 0.40}"
        Text: -0.35, "right", 4.5, "half", "L HH"
        Colour: "{0.25, 0.45, 0.75}"
        Text: -0.35, "right", 3.5, "half", "L Snare"
        Colour: "{0.78, 0.28, 0.22}"
        Text: -0.35, "right", 2.5, "half", "R Bass"
        Colour: "{0.35, 0.60, 0.40}"
        Text: -0.35, "right", 1.5, "half", "R HH"
        Colour: "{0.25, 0.45, 0.75}"
        Text: -0.35, "right", 0.5, "half", "R Snare"
    else
        Text top: "no", "Actual groove grid – colour = source class"
        Font size: 6
        Colour: "{0.78, 0.28, 0.22}"
        Text: -0.35, "right", 3, "half", "Bass"
        Colour: "{0.35, 0.60, 0.40}"
        Text: -0.35, "right", 2, "half", "HH"
        Colour: "{0.25, 0.45, 0.75}"
        Text: -0.35, "right", 1, "half", "Snare"
    endif
    Colour: "Black"
    Font size: 7
    Text bottom: "yes", "16th-note position"

    # ----------------------------------------------------------
    # SUMMARY STRIP
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.95, 7.58
    Select inner viewport: 0.60, 7.70, 7.01, 7.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.72, "half",
        ... "##Detected##  " + string$(numberOfEvents) + " events: "
        ... + string$(numBass) + " Bass / " + string$(numHH) + " HH / " + string$(numSnare) + " Snare"
        ... + "  |  ##Groove##  " + patternName$ + ", " + fixed$(tempo_BPM, 0) + " BPM, density " + fixed$(groove_density, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "##Render##  " + channelMode$ + " | " + hitSummary$
        ... + " | clip <= " + fixed$(clip_max_length_s * 1000, 0) + " ms"
        ... + " | envelope " + fixed$(attack_time_s * 1000, 1) + "/" + fixed$(release_time_s * 1000, 1) + " ms"
        ... + " | output " + fixed$(patternDuration, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Cleanup visualization object and restore full-page viewport for export.
    removeObject: vizSource
    Select outer viewport: 0, 8, 0, 7.58
    Select inner viewport: 0, 8, 0, 7.58
    Font size: 10
    Colour: "Black"
    Line width: 1
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