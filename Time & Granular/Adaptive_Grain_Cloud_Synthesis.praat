# ============================================================
# Praat AudioTools - Adaptive_Grain_Cloud_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fast multi-track overlap
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive granular resynthesis from input audio.
#   Uses multi-track concatenation for fast overlap.
#
# Changelog v0.3:
#   - FAST: Multi-track approach (concatenate then sum)
#   - Proper grain overlap via interleaved tracks
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
    real Position_scatter_(0-1) 0.2
    
    comment === Processing ===
    boolean Adaptive_duration 1
    boolean Reverse_random 0
    
    comment === Output ===
    real Output_duration_factor 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

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
    density = 4.0
    pitch_scatter_semitones = 0.0
    position_scatter = 0.0
    adaptive_duration = 0
    reverse_random = 0
    output_duration_factor = 2.0
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
    density = 2.0
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

original = selected("Sound")
original_name$ = selected$("Sound")
uid$ = string$(randomInteger(10000, 99999))

# === Convert to Mono ===
selectObject: original
Convert to mono
source = selected("Sound")
Rename: "src_" + uid$

selectObject: source
sourceDuration = Get total duration
sampleRate = Get sampling frequency

# === Validate ===
grainDurBase = grain_size_ms / 1000
if sourceDuration < grainDurBase
    removeObject: source
    exitScript: "Sound is shorter than grain size"
endif

# === Calculate Parameters ===
outputDuration = sourceDuration * output_duration_factor
hopTime = grainDurBase * (1 - grain_overlap)
if hopTime < 0.005
    hopTime = 0.005
endif

# Number of overlapping tracks needed
numTracks = ceiling(1 / (1 - grain_overlap + 0.001))
if numTracks < 1
    numTracks = 1
endif
if numTracks > 8
    numTracks = 8
endif

# Grains per track
grainsPerTrack = round(outputDuration / (grainDurBase * numTracks) * density)
totalGrains = grainsPerTrack * numTracks

# Safety
if grainsPerTrack > 500
    grainsPerTrack = 500
    totalGrains = grainsPerTrack * numTracks
endif

# === Info ===
writeInfoLine: "=== Adaptive Grain Cloud Synthesis ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(sourceDuration, 2), " s)"
appendInfoLine: "Grain size: ", grain_size_ms, " ms"
appendInfoLine: "Overlap: ", grain_overlap * 100, "%"
appendInfoLine: "Tracks: ", numTracks, " (for overlap)"
appendInfoLine: "Grains per track: ", grainsPerTrack
appendInfoLine: "Total grains: ", totalGrains
appendInfoLine: ""

# === Pre-analyze for Adaptive Duration ===
if adaptive_duration
    appendInfoLine: "Analyzing source spectrum..."
    numWindows = 20
    windowDur = sourceDuration / numWindows
    
    for w to numWindows
        selectObject: source
        Extract part: (w-1)*windowDur, w*windowDur, "Hanning", 1, 0
        temp = selected("Sound")
        To Spectrum: "yes"
        spec = selected("Spectrum")
        centroid[w] = Get centre of gravity: 2
        removeObject: spec, temp
        # Guard: if window was silent, Get centre of gravity returns undefined
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
    if cRange < 100
        cRange = 100
    endif
endif

# === Generate Tracks (FAST!) ===
appendInfoLine: "Generating grain tracks..."

for track to numTracks
    appendInfoLine: "  Track ", track, "/", numTracks
    
    # Collect grains for this track
    grainCount = 0
    
    for g to grainsPerTrack
        # Source position (sequential with scatter)
        basePos = (g - 1) / grainsPerTrack * sourceDuration
        if position_scatter > 0
            sourcePos = basePos + randomGauss(0, position_scatter * sourceDuration * 0.15)
        else
            sourcePos = basePos
        endif
        
        if sourcePos < 0
            sourcePos = 0
        endif
        if sourcePos > sourceDuration - grainDurBase
            sourcePos = sourceDuration - grainDurBase
        endif
        
        # Adaptive duration
        if adaptive_duration
            wIdx = floor(sourcePos / windowDur) + 1
            if wIdx < 1
                wIdx = 1
            endif
            if wIdx > numWindows
                wIdx = numWindows
            endif
            normC = (centroid[wIdx] - minC) / cRange
            durMult = 1.4 - normC * 0.8
            grainDur = grainDurBase * durMult
        else
            grainDur = grainDurBase
        endif
        
        if sourcePos + grainDur > sourceDuration
            grainDur = sourceDuration - sourcePos
        endif
        if grainDur < 0.01
            grainDur = 0.01
        endif
        # Safety: if either value is still undefined, skip this grain
        if sourcePos = undefined or grainDur = undefined
            goto SKIP_GRAIN
        endif
        
        # Extract grain
        selectObject: source
        Extract part: sourcePos, sourcePos + grainDur, "Hanning", 1, 0
        grain = selected("Sound")
        
        # Optional reverse
        if reverse_random and randomUniform(0, 1) > 0.5
            Reverse
        endif
        
        # Optional pitch shift
        if pitch_scatter_semitones > 0
            shift = randomGauss(0, pitch_scatter_semitones)
            if abs(shift) > 0.1
                ratio = 2 ^ (shift / 12)
                Override sampling frequency: sampleRate * ratio
                Resample: sampleRate, 50
                shifted = selected("Sound")
                removeObject: grain
                grain = shifted
            endif
        endif
        
        grainCount += 1
        grainID[track, grainCount] = grain
        label SKIP_GRAIN
    endfor
    
    grainTotal[track] = grainCount
endfor

# === Concatenate Each Track ===
appendInfoLine: "Concatenating tracks..."

for track to numTracks
    trackName$ = "track_" + uid$ + "_" + string$(track)
    
    if grainTotal[track] > 0
        selectObject: grainID[track, 1]
        for g from 2 to grainTotal[track]
            plusObject: grainID[track, g]
        endfor
        Concatenate
        trackSound[track] = selected("Sound")
        Rename: trackName$
        
        # Clean up grains
        for g to grainTotal[track]
            removeObject: grainID[track, g]
        endfor
        
        # Pad/trim to output duration
        selectObject: trackSound[track]
        trackDur = Get total duration
        
        if trackDur < outputDuration
            # Pad with silence
            silence = Create Sound from formula: "sil", 1, 0, outputDuration - trackDur, sampleRate, "0"
            selectObject: trackSound[track], silence
            Concatenate
            padded = selected("Sound")
            Rename: trackName$
            removeObject: trackSound[track], silence
            trackSound[track] = padded
        elsif trackDur > outputDuration
            # Trim
            selectObject: trackSound[track]
            Extract part: 0, outputDuration, "rectangular", 1, 0
            trimmed = selected("Sound")
            Rename: trackName$
            removeObject: trackSound[track]
            trackSound[track] = trimmed
        endif
        
        # Apply track offset (shift in time for overlap)
        if track > 1
            selectObject: trackSound[track]
            offsetAmount = (track - 1) / numTracks * grainDurBase
            offsetSamples = round(offsetAmount * sampleRate)
            Formula: "if col > offsetSamples then self[col - offsetSamples] else 0 fi"
        endif
    endif
endfor

# === Sum All Tracks ===
appendInfoLine: "Mixing tracks..."

selectObject: trackSound[1]
Copy: "output_" + uid$
output = selected("Sound")

for track from 2 to numTracks
    trackName$ = "track_" + uid$ + "_" + string$(track)
    selectObject: output
    Formula: "self + Sound_" + trackName$ + "[col]"
endfor

# Clean up tracks
for track to numTracks
    removeObject: trackSound[track]
endfor

# === Normalize ===
selectObject: output
Scale peak: 0.9
Fade in: 0, 0, 0.01, "yes"
Fade out: 0, outputDuration - 0.02, 0.02, "yes"
Rename: original_name$ + "_grainCloud"

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Grain Cloud: " + original_name$
    
    # Source
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
    
    # Output
    Select outer viewport: 0, 8, 2.6, 4.2
    Select inner viewport: 0.6, 7.6, 2.7, 4.1
    selectObject: output
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Spectrogram
    Select outer viewport: 0, 8, 4.4, 6.2
    Select inner viewport: 0.6, 7.6, 4.5, 6.1
    selectObject: output
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: spectrogram
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 6.3, 6.6
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "Grains: " + string$(totalGrains) + " | Tracks: " + string$(numTracks) + " | Size: " + string$(grain_size_ms) + "ms"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: source

# === Play ===
if play_result
    selectObject: output
    Play
endif

selectObject: output

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")