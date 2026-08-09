# ============================================================
# Praat AudioTools - Adaptive_Grain_Cloud_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - sample-accurate density-aware overlap-add
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive granular resynthesis from input audio.
#   Grains are scheduled on a sample-quantized event grid and
#   interleaved over non-overlapping tracks, then summed.
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
writeInfoLine: "=== Adaptive Grain Cloud Synthesis v0.5 ==="
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

        if reverse_random and randomUniform(0, 1) > 0.5
            Reverse
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

    Select outer viewport: 1, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Grain Cloud: " + original_name$

    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.6, 7.6, 1.0, 2.4
    selectObject: source
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 1.5, 1.8
    Text left: "yes", "Source"

    Select outer viewport: 0, 8, 2.6, 4.2
    Select inner viewport: 0.6, 7.6, 2.7, 4.1
    selectObject: output
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 4.4, 6.2
    Select inner viewport: 0.6, 7.6, 4.5, 6.1
    selectObject: output

    spectrogramMaxHz = 5000
    nyquist = sampleRate / 2
    if spectrogramMaxHz > 0.95 * nyquist
        spectrogramMaxHz = 0.95 * nyquist
    endif

    spectroWindow = 0.03
    if 2 * spectroWindow > outputDuration
        spectroWindow = outputDuration / 2
    endif

    if spectroWindow > 0 and spectrogramMaxHz > 0
        To Spectrogram: spectroWindow, spectrogramMaxHz, 0.01, 20, "Gaussian"
        spectrogram = selected("Spectrogram")
        Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
        removeObject: spectrogram
    endif

    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 6.3, 6.6
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "Grains: " + string$(totalGrains) + " | Event hop: " + fixed$(eventHop * 1000, 2) + " ms | Tracks: " + string$(numTracks)

    Font size: 10
    Colour: "Black"
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
