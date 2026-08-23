# ============================================================
# Praat AudioTools - Adaptive_Grain_Cloud_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026) - library-aligned process visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive granular resynthesis from input audio.
#   Grains are scheduled on a sample-quantized event grid and
#   interleaved over non-overlapping tracks, then summed.
#
# Changelog v0.5.1:
#   - Library-aligned visualization: source, grain time map, output, summary
#   - Grain map shows source interval -> output interval for every scheduled grain
#   - Reverse grains are shown with downward mappings; DSP is unchanged
#   - Dynamic object names are display-sanitized for Praat Picture text
#
# Changelog v0.5:
#   - Density now controls the actual event rate: hop / density
#   - Sample-quantized scheduling prevents cumulative onset drift
#   - Track slots preserve exact grain onset times during concatenation
#   - Scheduler automatically relaxes density if track/grain safety caps require it
#   - Adaptive-duration flat-spectrum case now maps to neutral duration (1.0x)
#   - Spectral Freeze preset freezes the source read pointer at the midpoint
#   - Time Stretch preset retuned for the new density semantics
#   - Pitch scatter is limited to +/-3 sigma for bounded scheduling
#   - Safer parameter validation, edge handling, normalization and fades
#   - ID-based mixing replaces fragile object-name formula references
#
# Changelog v0.4:
#   - Hop-based grain scheduling and track offsets
#   - Interleaved tracks: grain g -> track ((g-1) mod N)+1
#   - Source read pointer wraps for stretch/compress presets
#   - Empty-track guard, mix headroom, clearer info
# Changelog v0.3:
#   - FAST: Multi-track approach (concatenate then sum)
# ============================================================

form Adaptive Grain Cloud Synthesis
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Cloud
        option Micro-Grains
        option Long Grains
        option Spectral Freeze
        option Rhythmic Scatter
        option Chaotic Swarm
        option Time Stretch 2x
        option Time Compress 0.5x

    comment === Grain Parameters ===
    positive Grain_size_ms 50
    real Grain_overlap_(0-0.9) 0.5
    positive Density 2.0

    comment === Scatter ===
    real Pitch_scatter_semitones 0.0
    comment (Gaussian sigma; pitch shifting also changes grain duration)
    real Position_scatter_(0-1) 0.2

    comment === Processing ===
    boolean Adaptive_duration 1
    boolean Reverse_random 0

    comment === Output ===
    positive Output_duration_factor 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Internal safety / performance limits ===
maxTracks = 24
maxTotalGrains = 10000
minEventHop_s = 0.001
positionScatterScale = 0.15
adaptiveMinMult = 0.6
adaptiveMaxMult = 1.4
pitchSigmaLimit = 3.0
pitchHardLimit_semitones = 24.0

freezeMode = 0

# === Apply Presets ===
if preset = 2
    grain_size_ms = 40
    grain_overlap = 0.7
    density = 3.0
    pitch_scatter_semitones = 0.0
    position_scatter = 0.1
    adaptive_duration = 1
    reverse_random = 0
    output_duration_factor = 1.0
elsif preset = 3
    grain_size_ms = 100
    grain_overlap = 0.4
    density = 0.5
    pitch_scatter_semitones = 0.5
    position_scatter = 0.3
    adaptive_duration = 1
    reverse_random = 1
    output_duration_factor = 1.0
elsif preset = 4
    grain_size_ms = 10
    grain_overlap = 0.5
    density = 5.0
    pitch_scatter_semitones = 1.0
    position_scatter = 0.1
    adaptive_duration = 0
    reverse_random = 0
    output_duration_factor = 1.0
elsif preset = 5
    grain_size_ms = 200
    grain_overlap = 0.8
    density = 1.5
    pitch_scatter_semitones = 0.0
    position_scatter = 0.05
    adaptive_duration = 1
    reverse_random = 0
    output_duration_factor = 1.0
elsif preset = 6
    grain_size_ms = 80
    grain_overlap = 0.9
    density = 2.0
    pitch_scatter_semitones = 0.0
    position_scatter = 0.0
    adaptive_duration = 0
    reverse_random = 0
    output_duration_factor = 2.0
    freezeMode = 1
elsif preset = 7
    grain_size_ms = 30
    grain_overlap = 0.0
    density = 2.0
    pitch_scatter_semitones = 0.2
    position_scatter = 0.5
    adaptive_duration = 0
    reverse_random = 0
    output_duration_factor = 1.0
elsif preset = 8
    grain_size_ms = 25
    grain_overlap = 0.6
    density = 4.0
    pitch_scatter_semitones = 2.0
    position_scatter = 0.8
    adaptive_duration = 1
    reverse_random = 1
    output_duration_factor = 1.5
elsif preset = 9
    grain_size_ms = 60
    grain_overlap = 0.75
    density = 1.0
    pitch_scatter_semitones = 0.0
    position_scatter = 0.0
    adaptive_duration = 1
    reverse_random = 0
    output_duration_factor = 2.0
elsif preset = 10
    grain_size_ms = 40
    grain_overlap = 0.7
    density = 1.0
    pitch_scatter_semitones = 0.0
    position_scatter = 0.0
    adaptive_duration = 1
    reverse_random = 0
    output_duration_factor = 0.5
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

# === Validate user parameters ===
if grain_overlap < 0 or grain_overlap > 0.9
    exitScript: "Grain overlap must be between 0 and 0.9"
endif
if pitch_scatter_semitones < 0
    exitScript: "Pitch scatter must be zero or positive"
endif
if position_scatter < 0 or position_scatter > 1
    exitScript: "Position scatter must be between 0 and 1"
endif
if output_duration_factor <= 0
    exitScript: "Output duration factor must be positive"
endif

original = selected("Sound")
original_name$ = selected$("Sound")
display_name$ = replace$(original_name$, "_", " ", 0)

if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Dense Cloud"
elsif preset = 3
    presetName$ = "Sparse Cloud"
elsif preset = 4
    presetName$ = "Micro-Grains"
elsif preset = 5
    presetName$ = "Long Grains"
elsif preset = 6
    presetName$ = "Spectral Freeze"
elsif preset = 7
    presetName$ = "Rhythmic Scatter"
elsif preset = 8
    presetName$ = "Chaotic Swarm"
elsif preset = 9
    presetName$ = "Time Stretch 2x"
else
    presetName$ = "Time Compress 0.5x"
endif

uid$ = string$(randomInteger(10000, 99999))

# === Convert to Mono ===
selectObject: original
Convert to mono
source = selected("Sound")
Rename: "src_" + uid$

selectObject: source
sourceStart = Get start time
sourceEnd = Get end time
sourceDuration = Get total duration
sampleRate = Get sampling frequency
sourceSamples = Get number of samples

# === Validate source / grain ===
grainDurBase = grain_size_ms / 1000
if sourceDuration < grainDurBase
    removeObject: source
    exitScript: "Sound is shorter than grain size"
endif

grainBaseSamples = round(grainDurBase * sampleRate)
if grainBaseSamples < 1
    removeObject: source
    exitScript: "Grain size is shorter than one sample at this sampling frequency"
endif

# === Calculate sample-quantized scheduler ===
outputSamples = round(sourceSamples * output_duration_factor)
if outputSamples < 1
    outputSamples = 1
endif
outputDuration = outputSamples / sampleRate

baseHop = grainDurBase * (1 - grain_overlap)
requestedEventHop = baseHop / density

minHopSamples = round(minEventHop_s * sampleRate)
if minHopSamples < 1
    minHopSamples = 1
endif

eventHopSamples = round(requestedEventHop * sampleRate)
if eventHopSamples < minHopSamples
    eventHopSamples = minHopSamples
endif

# Bound the Gaussian pitch scatter so the scheduler can guarantee
# that grains assigned to the same track never overlap.
maxPitchShift = pitchSigmaLimit * pitch_scatter_semitones
if maxPitchShift > pitchHardLimit_semitones
    maxPitchShift = pitchHardLimit_semitones
endif

maxDurationMult = 1.0
if adaptive_duration
    maxDurationMult = adaptiveMaxMult
endif
if maxPitchShift > 0
    maxDurationMult = maxDurationMult * 2 ^ (maxPitchShift / 12)
endif

plannedMaxGrainSamples = ceiling(grainDurBase * maxDurationMult * sampleRate) + 2

# Cap total grain count by relaxing the event rate, not by truncating the tail.
grainCapHopSamples = ceiling(outputSamples / maxTotalGrains)
if grainCapHopSamples < 1
    grainCapHopSamples = 1
endif
if eventHopSamples < grainCapHopSamples
    eventHopSamples = grainCapHopSamples
endif

# Cap track count by relaxing the event rate. This preserves full grain
# durations and exact onset scheduling instead of allowing within-track drift.
trackCapHopSamples = ceiling(plannedMaxGrainSamples / maxTracks)
if trackCapHopSamples < 1
    trackCapHopSamples = 1
endif
if eventHopSamples < trackCapHopSamples
    eventHopSamples = trackCapHopSamples
endif

eventHop = eventHopSamples / sampleRate
totalGrains = ceiling(outputSamples / eventHopSamples)
if totalGrains < 1
    totalGrains = 1
endif

numTracks = ceiling(plannedMaxGrainSamples / eventHopSamples)
if numTracks < 1
    numTracks = 1
endif
if numTracks > totalGrains
    numTracks = totalGrains
endif
if numTracks > maxTracks
    numTracks = maxTracks
endif

trackStrideSamples = numTracks * eventHopSamples
trackStride = trackStrideSamples / sampleRate
effectiveDensity = baseHop / eventHop

densityLimited = 0
if eventHop > requestedEventHop + 0.5 / sampleRate
    densityLimited = 1
endif

mixScale = 1 / sqrt(numTracks)

# === Info ===
writeInfoLine: "=== Adaptive Grain Cloud Synthesis v0.5.1 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(sourceDuration, 3), " s)"
appendInfoLine: "Output duration: ", fixed$(outputDuration, 3), " s"
appendInfoLine: "Grain size: ", grain_size_ms, " ms"
appendInfoLine: "Base hop: ", fixed$(baseHop * 1000, 3), " ms"
appendInfoLine: "Event hop: ", fixed$(eventHop * 1000, 3), " ms"
appendInfoLine: "Requested density: ", fixed$(density, 3), " | Effective density: ", fixed$(effectiveDensity, 3)
appendInfoLine: "Tracks: ", numTracks, " | Track stride: ", fixed$(trackStride * 1000, 3), " ms"
appendInfoLine: "Total grains: ", totalGrains
if densityLimited
    appendInfoLine: "  NOTE: event density was reduced by the safety/performance limits."
endif
if maxPitchShift > 0
    appendInfoLine: "Pitch scatter limit: +/-", fixed$(maxPitchShift, 2), " semitones (", pitchSigmaLimit, " sigma, hard max ", pitchHardLimit_semitones, ")"
endif
if freezeMode
    appendInfoLine: "Freeze mode: source read pointer fixed at midpoint"
endif
appendInfoLine: ""

# === Pre-analyze for Adaptive Duration ===
adaptiveContrast = 0
if adaptive_duration
    appendInfoLine: "Analyzing source spectrum..."

    numWindows = 20
    if sourceDuration < 1.0
        numWindows = 10
    endif
    if sourceDuration < 0.25
        numWindows = 5
    endif

    windowDur = sourceDuration / numWindows

    for w to numWindows
        selectObject: source
        Extract part: sourceStart + (w-1)*windowDur, sourceStart + w*windowDur, "Hanning", 1, 0
        temp = selected("Sound")
        To Spectrum: "yes"
        spec = selected("Spectrum")
        centroid[w] = Get centre of gravity: 2
        removeObject: spec, temp

        if centroid[w] = undefined
            centroid[w] = 1000
        endif
    endfor

    minC = centroid[1]
    maxC = centroid[1]
    for w from 2 to numWindows
        if centroid[w] < minC
            minC = centroid[w]
        endif
        if centroid[w] > maxC
            maxC = centroid[w]
        endif
    endfor

    cRange = maxC - minC
    if cRange >= 100
        adaptiveContrast = 1
    endif
endif

# === Generate exact-onset tracks ===
appendInfoLine: "Generating sample-scheduled grain tracks..."

overflowCount = 0

for track to numTracks
    trackName$ = "track_" + uid$ + "_" + string$(track)
    segmentCount = 0

    # Initial offset establishes the interleaved event phase for this track.
    offsetSamples = (track - 1) * eventHopSamples
    if offsetSamples > 0
        offsetDur = offsetSamples / sampleRate
        leadingSilence = Create Sound from formula: "slotSil", 1, 0, offsetDur, sampleRate, "0"
        segmentCount += 1
        segmentID[segmentCount] = leadingSilence
    endif

    g = track
    while g <= totalGrains
        outputSample = (g - 1) * eventHopSamples
        outputTime = outputSample / sampleRate

        # Linear source traversal for normal/stretch/compress modes.
        # The final valid base-grain start is used as the endpoint.
        maxSourcePos = sourceEnd - grainDurBase
        if maxSourcePos < sourceStart
            maxSourcePos = sourceStart
        endif

        if freezeMode
            readPos = sourceStart + 0.5 * (maxSourcePos - sourceStart)
        else
            progress = outputTime / outputDuration
            if progress < 0
                progress = 0
            endif
            if progress > 1
                progress = 1
            endif
            readPos = sourceStart + progress * (maxSourcePos - sourceStart)
        endif

        basePos = readPos
        if position_scatter > 0
            sourcePos = basePos + randomGauss(0, position_scatter * sourceDuration * positionScatterScale)
        else
            sourcePos = basePos
        endif

        if sourcePos < sourceStart
            sourcePos = sourceStart
        endif
        if sourcePos > maxSourcePos
            sourcePos = maxSourcePos
        endif

        # Adaptive duration: low centroid -> longer grain, high centroid -> shorter.
        # A source with little centroid variation is mapped to the neutral 1.0x case.
        if adaptive_duration
            wIdx = floor((sourcePos - sourceStart) / windowDur) + 1
            if wIdx < 1
                wIdx = 1
            endif
            if wIdx > numWindows
                wIdx = numWindows
            endif

            if adaptiveContrast
                normC = (centroid[wIdx] - minC) / cRange
                if normC < 0
                    normC = 0
                endif
                if normC > 1
                    normC = 1
                endif
            else
                normC = 0.5
            endif

            grainDur = grainDurBase * (adaptiveMaxMult - normC * (adaptiveMaxMult - adaptiveMinMult))
        else
            grainDur = grainDurBase
        endif

        # Preserve requested grain duration at the end of the source by moving
        # the start backward, instead of shortening the grain whenever possible.
        if grainDur > sourceDuration
            grainDur = sourceDuration
            sourcePos = sourceStart
        elsif sourcePos + grainDur > sourceEnd
            sourcePos = sourceEnd - grainDur
        endif
        if sourcePos < sourceStart
            sourcePos = sourceStart
        endif

        selectObject: source
        Extract part: sourcePos, sourcePos + grainDur, "Hanning", 1, 0
        grain = selected("Sound")

        grainWasReversed = 0
        if reverse_random and randomUniform(0, 1) > 0.5
            Reverse
            grainWasReversed = 1
        endif

        if pitch_scatter_semitones > 0
            shift = randomGauss(0, pitch_scatter_semitones)
            if shift > maxPitchShift
                shift = maxPitchShift
            endif
            if shift < -maxPitchShift
                shift = -maxPitchShift
            endif

            if abs(shift) > 0.1
                ratio = 2 ^ (shift / 12)
                Override sampling frequency: sampleRate * ratio
                Resample: sampleRate, 50
                shifted = selected("Sound")
                removeObject: grain
                grain = shifted
            endif
        endif

        selectObject: grain
        grainSamples = Get number of samples

        # Visualization-only mapping data: source interval -> output interval.
        # These arrays do not participate in synthesis.
        mapOut0[g] = outputTime
        mapOut1[g] = outputTime + grainSamples / sampleRate
        if mapOut1[g] > outputDuration
            mapOut1[g] = outputDuration
        endif
        if grainWasReversed
            mapSrc0[g] = sourcePos + grainDur
            mapSrc1[g] = sourcePos
        else
            mapSrc0[g] = sourcePos
            mapSrc1[g] = sourcePos + grainDur
        endif

        # This should only trigger for a rounding edge case. Keeping the guard
        # prevents one oversized grain from shifting every later onset in a track.
        if grainSamples > trackStrideSamples
            overflowCount += 1
            slotDur = trackStrideSamples / sampleRate
            Extract part: 0, slotDur, "rectangular", 1, 0
            trimmedGrain = selected("Sound")
            removeObject: grain
            grain = trimmedGrain
            selectObject: grain
            grainSamples = Get number of samples
        endif

        segmentCount += 1
        segmentID[segmentCount] = grain

        # Pad each grain to one exact track slot. Since the slot size is an
        # integer number of samples, concatenation cannot accumulate timing drift.
        padSamples = trackStrideSamples - grainSamples
        if padSamples > 0
            padDur = padSamples / sampleRate
            slotSilence = Create Sound from formula: "slotSil", 1, 0, padDur, sampleRate, "0"
            segmentCount += 1
            segmentID[segmentCount] = slotSilence
        endif

        g += numTracks
    endwhile

    appendInfoLine: "  Track ", track, "/", numTracks, " (", segmentCount, " segments)"

    selectObject: segmentID[1]
    for s from 2 to segmentCount
        plusObject: segmentID[s]
    endfor
    Concatenate
    trackSound[track] = selected("Sound")
    Rename: trackName$

    for s to segmentCount
        removeObject: segmentID[s]
    endfor

    # Force every track to the exact output sample count.
    selectObject: trackSound[track]
    trackSamples = Get number of samples

    if trackSamples < outputSamples
        missingSamples = outputSamples - trackSamples
        missingDur = missingSamples / sampleRate
        tailSilence = Create Sound from formula: "tailSil", 1, 0, missingDur, sampleRate, "0"
        selectObject: trackSound[track], tailSilence
        Concatenate
        padded = selected("Sound")
        Rename: trackName$
        removeObject: trackSound[track], tailSilence
        trackSound[track] = padded
    elsif trackSamples > outputSamples
        selectObject: trackSound[track]
        Extract part: 0, outputDuration, "rectangular", 1, 0
        trimmed = selected("Sound")
        Rename: trackName$
        removeObject: trackSound[track]
        trackSound[track] = trimmed
    endif
endfor

if overflowCount > 0
    appendInfoLine: "WARNING: ", overflowCount, " grain(s) exceeded a track slot by rounding and were trimmed."
endif

# === Sum All Tracks ===
appendInfoLine: "Mixing tracks..."

selectObject: trackSound[1]
Copy: "output_" + uid$
output = selected("Sound")

selectObject: output
Formula: ~ self * mixScale

for track from 2 to numTracks
    otherTrack = trackSound[track]
    selectObject: output
    Formula: ~ self + mixScale * object [otherTrack, row, col]
endfor

for track to numTracks
    removeObject: trackSound[track]
endfor

# === Normalize and edge fades ===
selectObject: output
peak = Get absolute extremum: 0, 0, "none"
if peak > 0
    Scale peak: 0.9
endif

fadeDur = 0.01
if 4 * fadeDur > outputDuration
    fadeDur = outputDuration / 4
endif
if fadeDur > 0
    Fade in: 0, 0, fadeDur, "yes"
    Fade out: 0, outputDuration - fadeDur, fadeDur, "yes"
endif

Rename: original_name$ + "_grainCloud"

# === Visualization ===
if draw_visualization
    Erase all
    Colour: "Black"
    Font size: 10
    Line width: 1
    Solid line

    # Title / subtitle
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Adaptive Grain Cloud Synthesis##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Adaptive Grain Cloud Synthesis.praat  |  " + presetName$ + "  |  " + display_name$

    # Source
    Select outer viewport: 0, 8, 0.65, 2.00
    Select inner viewport: 0.55, 7.55, 0.80, 1.86
    Axes: sourceStart, sourceEnd, -1.35, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", sourceStart, sourceEnd, -1.35, 1.15
    selectObject: source
    Colour: "{0.55, 0.55, 0.55}"
    Draw: sourceStart, sourceEnd, -1, 1, "no", "Curve"
    Select outer viewport: 0, 8, 0.65, 2.00
    Select inner viewport: 0.55, 7.55, 0.80, 1.86
    Axes: sourceStart, sourceEnd, -1.35, 1.15
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Source time (s)"
    Text: sourceStart + 0.01 * sourceDuration, "left", 1.04, "half", "##Source##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: sourceEnd - 0.01 * sourceDuration, "right", 1.04, "half", "" + fixed$(sourceDuration, 2) + " s  |  mono analysis/render source"

    # Grain time map: every line is one source interval mapped to one output interval.
    Select outer viewport: 0, 8, 2.15, 3.80
    Select inner viewport: 0.55, 7.55, 2.30, 3.66
    Axes: sourceStart, sourceEnd, 0, outputDuration
    Paint rectangle: "{0.97, 0.97, 0.97}", sourceStart, sourceEnd, 0, outputDuration

    # Reference traversal.
    Colour: "{0.82, 0.82, 0.82}"
    Line width: 1
    if freezeMode
        freezeX = sourceStart + 0.5 * ((sourceEnd - grainDurBase) - sourceStart)
        if freezeX < sourceStart
            freezeX = sourceStart
        endif
        Draw line: freezeX, 0, freezeX, outputDuration
    else
        referenceEnd = sourceEnd - grainDurBase
        if referenceEnd < sourceStart
            referenceEnd = sourceStart
        endif
        Draw line: sourceStart, 0, referenceEnd, outputDuration
    endif

    Line width: 1.15
    for g to totalGrains
        if mapSrc1[g] < mapSrc0[g]
            Colour: "{0.48, 0.35, 0.74}"
        else
            Colour: "{0.22, 0.46, 0.82}"
        endif
        Draw line: mapSrc0[g], mapOut0[g], mapSrc1[g], mapOut1[g]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output time (s)"
    Text bottom: "yes", "Source time (s)"
    Text: sourceStart + 0.01 * sourceDuration, "left", 0.95 * outputDuration, "half", "##Grain time map##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: sourceStart + 0.01 * sourceDuration, "left", 0.84 * outputDuration, "half", "source interval -> output interval  |  purple/downward = reversed"
    Text: sourceEnd - 0.01 * sourceDuration, "right", 0.84 * outputDuration, "half", "event hop " + fixed$(eventHop * 1000, 2) + " ms"

    # Output
    Select outer viewport: 0, 8, 3.95, 5.30
    Select inner viewport: 0.55, 7.55, 4.10, 5.16
    Axes: 0, outputDuration, -1.35, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, -1.35, 1.15
    selectObject: output
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, outputDuration, -1, 1, "no", "Curve"
    Select outer viewport: 0, 8, 3.95, 5.30
    Select inner viewport: 0.55, 7.55, 4.10, 5.16
    Axes: 0, outputDuration, -1.35, 1.15
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Output time (s)"
    Text: 0.01 * outputDuration, "left", 1.04, "half", "##Output##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.99 * outputDuration, "right", 1.04, "half", "peak-normalized to 0.9  |  10 ms edge fades"

    if adaptive_duration
        adaptiveName$ = "on"
    else
        adaptiveName$ = "off"
    endif
    if reverse_random
        reverseName$ = "on"
    else
        reverseName$ = "off"
    endif

    # Summary
    Select outer viewport: 0, 8, 5.48, 6.55
    Select inner viewport: 0.25, 7.75, 5.56, 6.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.56, "half", "Grains " + string$(totalGrains) + "  |  Grain " + fixed$(grain_size_ms, 1) + " ms  |  Overlap " + fixed$(grain_overlap, 2) + "  |  Tracks " + string$(numTracks)
    Text: 0.02, "left", 0.33, "half", "Density " + fixed$(density, 2) + " -> " + fixed$(effectiveDensity, 2) + "  |  Position scatter " + fixed$(position_scatter, 2) + "  |  Pitch sigma " + fixed$(pitch_scatter_semitones, 2) + " st"
    Text: 0.02, "left", 0.12, "half", "Duration " + fixed$(sourceDuration, 2) + " -> " + fixed$(outputDuration, 2) + " s  |  Adaptive duration " + adaptiveName$ + "  |  Random reverse " + reverseName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Cleanup ===
removeObject: source

if play_result
    selectObject: output
    Play
endif

selectObject: output

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
