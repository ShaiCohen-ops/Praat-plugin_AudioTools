# ============================================================
# Praat AudioTools - Neural_Audio_Mosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Audio Mosaic - Reconstructs 'Target' using 'Source' grains
#   via feature matching (concatenative synthesis / musaicing).
#
# Changelog v0.6 (2026):
#   - FIX (audible): OLA gain was only correct at Overlap_ratio 0.5.
#     Full-length Hanning grains placed at grain*(1-overlap) sum to
#     a constant ONLY at 50% overlap: the Rhythmic preset (0.25)
#     left deep inter-grain dips, and CreativeLoose/HybridTexture
#     (0.6/0.65) produced a rippling over-overlapped sum. The crude
#     constant 1/(1+overlap) compensation could fix neither. v0.6
#     normalizes by the EXACT window-sum envelope: the bare Hanning
#     window is overlap-added once on the same grid, and each
#     channel is divided by it. Flat unity gain at ANY overlap
#     ratio (the knob becomes a pure grain-density/texture control),
#     output edges recover full level, gain_comp removed.
#     Measured on DC grains (isolating windowing from grain phase):
#     overlap 0.25: 10.7 dB dips -> 0.00002 dB; overlap 0.65:
#     0.26 dB ripple -> flat; overlap 0.5 was v0.5's only correct
#     case and stays flat. Note: phase interference between
#     overlapping grains from different source positions remains --
#     that is the granular texture itself, not a gain artifact.
#   - FIX: unvoiced frames contributed logF0 = 0 to the pitch
#     feature's min/max normalization pool, stretching the range
#     and compressing voiced pitch discrimination (e.g. all-high
#     voices squeezed into the upper half). Feature 13 is now
#     normalized over VOICED frames only (unvoiced values are never
#     read by the voicing-aware distance).
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Fixed Formula object references
#   - Added preset name to output
#
# Changelog v0.5 (2026):
#   - SPEED/PORTABILITY: OLA synthesis Formula replaced object(<id>, t)
#     time-interpolated reads with object[<id>, 1, col - offsetCol]
#     indexed-column reads. The grain and destination Sound share
#     the same sample rate (fs), so time interpolation was wasteful
#     two-sample linear interpolation per output sample (also a mild
#     low-pass filter at frequencies near Nyquist). Indexed reads
#     are direct sample-aligned copies — same math, faster, more
#     portable across Praat versions.
#   - QUALITY: Voiced/unvoiced tracking. v0.4 set logF0=0 for
#     unvoiced frames, which the distance metric then treated as
#     "100 Hz pitch" — indistinguishable from a real 100 Hz voiced
#     frame. Speech inputs with mixed voicing got nonsensical
#     pitch matches as a result. v0.5 tracks tValid_# and sValid_#
#     flags. The pitch term is included in the distance only if
#     BOTH the target and source frames are voiced. A small
#     voicing-mismatch penalty (0.25 * pitch_weight) discourages
#     voiced↔unvoiced cross-matches without forbidding them.
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly TWO Sound objects. (1=Target, 2=Source)"
endif

id1 = selected("Sound", 1)
id2 = selected("Sound", 2)

form Neural Audio Mosaic v0.6
    comment Select 2 Sounds: #1 = Target, #2 = Source
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Tight Match
        option Creative Loose
        option Rhythmic
        option Spectral Only
        option Pitch Priority
        option Hybrid Texture
    comment === Grain Parameters ===
    positive Grain_size_ms 50
    real Overlap_ratio 0.5
    comment === Search ===
    optionmenu Search_mode: 1
        option Stochastic (fast)
        option Exhaustive (accurate)
    integer Search_probes 50
    comment === Feature Weights ===
    positive Pitch_weight 1.0
    positive Spectral_weight 1.0
    positive Energy_weight 0.5
    comment === Output ===
    boolean Stereo_output 1
    real Stereo_variation 0.3
    boolean Normalize_volume 1
    boolean Play_result 1
endform

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Tight Match
    grain_size_ms = 40
    overlap_ratio = 0.5
    search_mode = 2
    pitch_weight = 1.2
    spectral_weight = 1.5
    energy_weight = 0.8
    stereo_variation = 0.15
    presetName$ = "TightMatch"
elsif preset = 3
    # Creative Loose
    grain_size_ms = 80
    overlap_ratio = 0.6
    search_mode = 1
    search_probes = 20
    pitch_weight = 0.3
    spectral_weight = 0.5
    energy_weight = 0.2
    stereo_variation = 0.5
    presetName$ = "CreativeLoose"
elsif preset = 4
    # Rhythmic
    grain_size_ms = 30
    overlap_ratio = 0.25
    search_mode = 1
    search_probes = 80
    pitch_weight = 0.5
    spectral_weight = 1.0
    energy_weight = 1.5
    stereo_variation = 0.25
    presetName$ = "Rhythmic"
elsif preset = 5
    # Spectral Only
    grain_size_ms = 60
    overlap_ratio = 0.5
    search_mode = 2
    pitch_weight = 0.0
    spectral_weight = 2.0
    energy_weight = 0.3
    stereo_variation = 0.3
    presetName$ = "SpectralOnly"
elsif preset = 6
    # Pitch Priority
    grain_size_ms = 50
    overlap_ratio = 0.5
    search_mode = 2
    pitch_weight = 3.0
    spectral_weight = 0.5
    energy_weight = 0.5
    stereo_variation = 0.2
    presetName$ = "PitchPriority"
elsif preset = 7
    # Hybrid Texture
    grain_size_ms = 70
    overlap_ratio = 0.65
    search_mode = 1
    search_probes = 40
    pitch_weight = 1.0
    spectral_weight = 1.0
    energy_weight = 1.0
    stereo_variation = 0.4
    presetName$ = "HybridTexture"
else
    presetName$ = "Manual"
endif

# ============================================
# SETUP
# ============================================

selectObject: id1
targetName$ = selected$("Sound")
durTarget = Get total duration
fsTarget = Get sampling frequency

selectObject: id2
sourceName$ = selected$("Sound")
durSource = Get total duration
fsSource = Get sampling frequency

if fsTarget <> fsSource
    exitScript: "Error: Both sounds must have the same sampling frequency."
endif

fs = fsTarget
grainSec = grain_size_ms / 1000
stepSec = grainSec * (1 - overlap_ratio)

if stepSec < 0.001
    stepSec = 0.001
endif

if durTarget < grainSec or durSource < grainSec
    exitScript: "Sounds are too short for this grain size."
endif

clearinfo
writeInfoLine: "=== Neural Audio Mosaic v0.6 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target: ", targetName$, " (", fixed$(durTarget, 2), " s)"
appendInfoLine: "Source: ", sourceName$, " (", fixed$(durSource, 2), " s)"
appendInfoLine: "Grain: ", grain_size_ms, " ms | Overlap: ", fixed$(overlap_ratio * 100, 0), "%"
if search_mode = 1
    appendInfoLine: "Search: Stochastic (", search_probes, " probes)"
else
    appendInfoLine: "Search: Exhaustive"
endif
if stereo_output
    appendInfoLine: "Output: Stereo (variation ", fixed$(stereo_variation * 100, 0), "%)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

# Make mono working copies
selectObject: id1
targetSnd = Convert to mono
Rename: "Work_Target"

selectObject: id2
sourceSnd = Convert to mono
Rename: "Work_Source"

# ============================================
# FEATURE EXTRACTION
# ============================================

appendInfoLine: "Extracting features..."

nTarget = floor((durTarget - grainSec) / stepSec)
nSource = floor((durSource - grainSec) / stepSec)

if nTarget < 1
    nTarget = 1
endif
if nSource < 1
    nSource = 1
endif

appendInfoLine: "  Target frames: ", nTarget
appendInfoLine: "  Source frames: ", nSource

nFeatures = 14

# Allocate target feature arrays
for f from 1 to nFeatures
    tFeat_'f'# = zero#(nTarget)
endfor
tTime# = zero#(nTarget)
# v0.5: voicing flag — 1 if frame had a valid pitch, 0 if unvoiced.
# Used by the distance metric to exclude the pitch term for unvoiced
# frames (see "NEURAL SEARCH" block below).
tValid# = zero#(nTarget)

# Allocate source feature arrays
for f from 1 to nFeatures
    sFeat_'f'# = zero#(nSource)
endfor
sTime# = zero#(nSource)
sValid# = zero#(nSource)

# Extract TARGET features
selectObject: targetSnd
tMfcc = To MFCC: 12, 0.025, stepSec, 100, 100, 0

selectObject: targetSnd
tPitch = To Pitch: stepSec, 75, 600

selectObject: targetSnd
tIntensity = To Intensity: 75, stepSec, "yes"

for i from 1 to nTarget
    t = (i - 0.5) * stepSec
    tTime#[i] = t
    
    selectObject: tMfcc
    for c from 1 to 12
        val = Get value in frame: i, c
        if val = undefined
            val = 0
        endif
        tFeat_'c'#[i] = val
    endfor
    
    selectObject: tPitch
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        logF0 = 0
        tValid#[i] = 0
    else
        logF0 = 12 * ln(f0 / 100) / ln(2)
        tValid#[i] = 1
    endif
    tFeat_13#[i] = logF0
    
    selectObject: tIntensity
    energy = Get value at time: t, "cubic"
    if energy = undefined
        energy = 50
    endif
    tFeat_14#[i] = energy
endfor

removeObject: tMfcc, tPitch, tIntensity

# Extract SOURCE features
selectObject: sourceSnd
sMfcc = To MFCC: 12, 0.025, stepSec, 100, 100, 0

selectObject: sourceSnd
sPitch = To Pitch: stepSec, 75, 600

selectObject: sourceSnd
sIntensity = To Intensity: 75, stepSec, "yes"

for i from 1 to nSource
    t = (i - 0.5) * stepSec
    sTime#[i] = t
    
    selectObject: sMfcc
    for c from 1 to 12
        val = Get value in frame: i, c
        if val = undefined
            val = 0
        endif
        sFeat_'c'#[i] = val
    endfor
    
    selectObject: sPitch
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        logF0 = 0
        sValid#[i] = 0
    else
        logF0 = 12 * ln(f0 / 100) / ln(2)
        sValid#[i] = 1
    endif
    sFeat_13#[i] = logF0
    
    selectObject: sIntensity
    energy = Get value at time: t, "cubic"
    if energy = undefined
        energy = 50
    endif
    sFeat_14#[i] = energy
endfor

removeObject: sMfcc, sPitch, sIntensity

appendInfoLine: "  Features extracted"

# v0.5: report voicing fraction
nTValid = 0
nSValid = 0
for i from 1 to nTarget
    nTValid = nTValid + tValid#[i]
endfor
for i from 1 to nSource
    nSValid = nSValid + sValid#[i]
endfor
appendInfoLine: "  Target voiced: ", nTValid, "/", nTarget,
    ... " (", fixed$(nTValid / nTarget * 100, 0), "%)"
appendInfoLine: "  Source voiced: ", nSValid, "/", nSource,
    ... " (", fixed$(nSValid / nSource * 100, 0), "%)"

# ============================================
# JOINT FEATURE NORMALIZATION
# ============================================

appendInfoLine: "Normalizing features..."

for f from 1 to nFeatures
    minV = 1e9
    maxV = -1e9
    
    # v0.6: feature 13 (pitch) pools min/max over VOICED frames only.
    # Unvoiced frames carry logF0 = 0, which stretched the range and
    # compressed voiced pitch discrimination; the voicing-aware
    # distance never reads unvoiced pitch values anyway.
    for i from 1 to nTarget
        if f <> 13 or tValid#[i] = 1
            v = tFeat_'f'#[i]
            if v < minV
                minV = v
            endif
            if v > maxV
                maxV = v
            endif
        endif
    endfor
    
    for i from 1 to nSource
        if f <> 13 or sValid#[i] = 1
            v = sFeat_'f'#[i]
            if v < minV
                minV = v
            endif
            if v > maxV
                maxV = v
            endif
        endif
    endfor
    
    # No voiced frames at all: leave feature 13 untouched
    if minV > maxV
        minV = 0
        maxV = 1
    endif
    
    range = maxV - minV
    if range < 1e-9
        range = 1
    endif
    
    for i from 1 to nTarget
        tFeat_'f'#[i] = (tFeat_'f'#[i] - minV) / range
    endfor
    
    for i from 1 to nSource
        sFeat_'f'#[i] = (sFeat_'f'#[i] - minV) / range
    endfor
endfor

# ============================================
# FEATURE WEIGHTS
# ============================================

totalWeight = spectral_weight * 12 + pitch_weight + energy_weight
if totalWeight < 0.001
    totalWeight = 1
endif

for c from 1 to 12
    w_'c' = spectral_weight * nFeatures / totalWeight
endfor
w_13 = pitch_weight * nFeatures / totalWeight
w_14 = energy_weight * nFeatures / totalWeight

# ============================================
# NEURAL SEARCH
# ============================================

appendInfoLine: "Running neural search..."

matchIdx# = zero#(nTarget)

if stereo_output
    matchIdx_R# = zero#(nTarget)
endif

for i from 1 to nTarget
    best_dist = 1e9
    best_idx = 1
    second_best_dist = 1e9
    second_best_idx = 1
    
    if search_mode = 2
        # Exhaustive
        # v0.5: distance is now split into "always include" (MFCC + energy)
        # and "voicing-aware" (pitch). Pitch term is added only if BOTH
        # frames are voiced. A small voicing-mismatch penalty discourages
        # voiced↔unvoiced cross-matches.
        tValid_i = tValid#[i]
        for j from 1 to nSource
            dist = 0
            # MFCC features 1..12
            for f from 1 to 12
                d = tFeat_'f'#[i] - sFeat_'f'#[j]
                dist += d * d * w_'f'
            endfor
            # Energy (feature 14)
            d14 = tFeat_14#[i] - sFeat_14#[j]
            dist += d14 * d14 * w_14
            # Pitch term — voicing-aware
            sValid_j = sValid#[j]
            if tValid_i = 1 and sValid_j = 1
                d13 = tFeat_13#[i] - sFeat_13#[j]
                dist += d13 * d13 * w_13
            elsif tValid_i <> sValid_j
                # Voicing mismatch penalty (small soft bias)
                dist += w_13 * 0.25
            endif
            
            if dist < best_dist
                second_best_dist = best_dist
                second_best_idx = best_idx
                best_dist = dist
                best_idx = j
            elsif dist < second_best_dist
                second_best_dist = dist
                second_best_idx = j
            endif
        endfor
    else
        # Stochastic — same voicing-aware distance as exhaustive
        tValid_i = tValid#[i]
        for probe from 1 to search_probes
            j = randomInteger(1, nSource)
            
            dist = 0
            for f from 1 to 12
                d = tFeat_'f'#[i] - sFeat_'f'#[j]
                dist += d * d * w_'f'
            endfor
            d14 = tFeat_14#[i] - sFeat_14#[j]
            dist += d14 * d14 * w_14
            sValid_j = sValid#[j]
            if tValid_i = 1 and sValid_j = 1
                d13 = tFeat_13#[i] - sFeat_13#[j]
                dist += d13 * d13 * w_13
            elsif tValid_i <> sValid_j
                dist += w_13 * 0.25
            endif
            
            if dist < best_dist
                second_best_dist = best_dist
                second_best_idx = best_idx
                best_dist = dist
                best_idx = j
            elsif dist < second_best_dist
                second_best_dist = dist
                second_best_idx = j
            endif
        endfor
    endif
    
    matchIdx#[i] = best_idx
    
    if stereo_output
        if randomUniform(0, 1) < stereo_variation
            matchIdx_R#[i] = second_best_idx
        else
            matchIdx_R#[i] = best_idx
        endif
    endif
    
    if i mod 100 = 0
        perc = i / nTarget * 100
        appendInfoLine: "  Matching: ", fixed$(perc, 0), "%"
    endif
endfor

appendInfoLine: "  Search complete"

# ============================================
# OVERLAP-ADD SYNTHESIS
# ============================================

appendInfoLine: "Synthesizing mosaic..."

outputDur = nTarget * stepSec + grainSec

# v0.6: exact window-sum envelope for OLA normalization. Overlap-add
# the bare Hanning window (obtained by windowing a constant-1 sound,
# so it matches Praat's Extract-part window exactly) on the same
# placement grid, once, shared by both channels. Dividing each
# channel by this envelope gives flat unity gain at ANY overlap
# ratio -- the old constant 1/(1+overlap) was only ever correct-ish
# at 0.5, dipping at low overlaps and rippling at high ones.
onesSnd = Create Sound from formula: "ones", 1, 0, grainSec, fs, "1"
selectObject: onesSnd
hannWin = Extract part: 0, grainSec, "Hanning", 1, "no"
removeObject: onesSnd
hannIdStr$ = string$(hannWin)

winSum = Create Sound from formula: "winsum", 1, 0, outputDur, fs, "0"
for i from 1 to nTarget
    destTime = (i - 1) * stepSec
    offsetCol = round(destTime * fs)
    offsetCol_str$ = string$(offsetCol)
    selectObject: winSum
    Formula (part): destTime, destTime + grainSec, 1, 1,
        ... "self + object[" + hannIdStr$
        ... + ", 1, col - " + offsetCol_str$ + "]"
endfor
removeObject: hannWin
winSumIdStr$ = string$(winSum)

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

for pass from 1 to n_passes
    if stereo_output
        if pass = 1
            appendInfoLine: "  LEFT channel..."
        else
            appendInfoLine: "  RIGHT channel..."
        endif
    endif
    
    outputSnd = Create Sound from formula: "Output_" + string$(pass), 1, 0, outputDur, fs, "0"
    
    for i from 1 to nTarget
        if pass = 1
            srcIdx = matchIdx#[i]
        else
            srcIdx = matchIdx_R#[i]
        endif
        
        t_src = sTime#[srcIdx]
        t1 = t_src - (grainSec / 2)
        t2 = t_src + (grainSec / 2)
        
        if t1 < 0
            t1 = 0
            t2 = grainSec
        endif
        if t2 > durSource
            t2 = durSource
            t1 = durSource - grainSec
            if t1 < 0
                t1 = 0
            endif
        endif
        
        selectObject: sourceSnd
        grain = Extract part: t1, t2, "Hanning", 1, "no"
        
        destTime = (i - 1) * stepSec
        
        selectObject: grain
        grainDur = Get total duration
        grainIdStr$ = string$(grain)
        
        # v0.5: indexed-column read instead of object(<id>, t) time-
        # interpolated read. Both grain and outputSnd are at fs sample
        # rate, so a sample-aligned copy via indexed cols is correct
        # and faster than time interpolation.
        offsetCol = round(destTime * fs)
        offsetCol_str$ = string$(offsetCol)
        
        selectObject: outputSnd
        Formula (part): destTime, destTime + grainDur, 1, 1,
            ... "self + object[" + grainIdStr$
            ... + ", 1, col - " + offsetCol_str$ + "]"
        
        removeObject: grain
    endfor
    
    # v0.6: normalize by the exact Hann window-sum envelope
    # (replaces the constant 1/(1+overlap) compensation)
    selectObject: outputSnd
    Formula: "self / (object[" + winSumIdStr$ + ", 1, col] + 1e-6)"
    
    if pass = 1
        channel_left = outputSnd
        selectObject: channel_left
        Rename: "Channel_Left"
    else
        channel_right = outputSnd
        selectObject: channel_right
        Rename: "Channel_Right"
    endif
endfor

removeObject: winSum

# ============================================
# COMBINE OUTPUT
# ============================================

if stereo_output
    appendInfoLine: "Combining to stereo..."
    
    selectObject: channel_left
    dur_L = Get total duration
    selectObject: channel_right
    dur_R = Get total duration
    
    if dur_L < dur_R
        selectObject: channel_right
        tmp = Extract part: 0, dur_L, "rectangular", 1, "no"
        removeObject: channel_right
        channel_right = tmp
    elsif dur_R < dur_L
        selectObject: channel_left
        tmp = Extract part: 0, dur_R, "rectangular", 1, "no"
        removeObject: channel_left
        channel_left = tmp
    endif
    
    selectObject: channel_left
    plusObject: channel_right
    finalOut = Combine to stereo
    Rename: targetName$ + "_Mosaic_" + presetName$
    
    removeObject: channel_left, channel_right
else
    finalOut = channel_left
    Rename: targetName$ + "_Mosaic_" + presetName$
endif

if normalize_volume
    selectObject: finalOut
    Scale peak: 0.99
endif

# ============================================================
# VISUALIZATION (Creative & Colorful AudioTools Style)
# ============================================================
Erase all

# Setup base font and styling
Helvetica
Line width: 1

# === GLOBAL HEADER ===
Select outer viewport: 0, 8, 0, 0.6
Select inner viewport: 0.8, 7.6, 0.1, 0.5
Axes: 0, 1, 0, 1

# Title and Subtitle
Font size: 14
Colour: "Black"
Text: 0.5, "centre", 0.6, "half", "NEURAL AUDIO MOSAIC"
Font size: 9
Colour: "{0.5, 0.5, 0.5}"
Text: 0.5, "centre", 0.1, "half", "Concatenative Synthesis Reconstruction Map"

# Divider Line
Line width: 2
Colour: "{0.2, 0.2, 0.2}"
Draw line: 0, -0.2, 1, -0.2
Line width: 1

# === PANEL 1: SOURCE WAVEFORM ===
Select outer viewport: 0, 8, 0.7, 2.0
Select inner viewport: 0.8, 7.6, 0.7, 1.9

selectObject: id2
# Cool Slate Blue
Colour: "{0.4, 0.5, 0.6}"
Draw: 0, 0, 0, 0, "no", "Curve"

Colour: "Black"
Draw inner box
Font size: 8
Select outer viewport: 0.15, 8, 0.7, 2.0
Text left: "yes", "Source"

# === PANEL 2: CREATIVE GRAIN TRAJECTORY MAP ===
Select outer viewport: 0, 8, 2.1, 4.5
Select inner viewport: 0.8, 7.6, 2.1, 4.3

Axes: 0, durTarget, 0, durSource
Colour: "Black"
Draw inner box
Font size: 8
Text left: "yes", "Source Time"
Text bottom: "no", "Target Time"

# 1. Draw the "Playhead Trajectory" (connecting lines)
Colour: "{0.85, 0.85, 0.85}"
Line width: 1
for g from 2 to nTarget
    x1 = tTime#[g-1]
    y1 = sTime#[matchIdx#[g-1]]
    x2 = tTime#[g]
    y2 = sTime#[matchIdx#[g]]
    Draw line: x1, y1, x2, y2
endfor

# 2. Draw mapping dots with dynamic color gradient
for g from 1 to nTarget
    x_pos = tTime#[g] 
    src_idx = matchIdx#[g]
    y_pos = sTime#[src_idx] 
    
    # Color morphs dynamically from Magenta (start) to Cyan (end)
    pos_ratio = y_pos / durSource
    cR = 0.8 - (0.7 * pos_ratio)
    cG = 0.2 + (0.6 * pos_ratio)
    cB = 0.6 + (0.3 * pos_ratio)
    
    color$ = "{" + fixed$(cR, 3) + "," + fixed$(cG, 3) + "," + fixed$(cB, 3) + "}"
    
    # Outer colored glow
    Paint circle (mm): color$, x_pos, y_pos, 1.6
    # Inner white core
    Paint circle (mm): "White", x_pos, y_pos, 0.5
endfor

# === PANEL 3: MOSAIC OUTPUT WAVEFORM ===
Select outer viewport: 0, 8, 4.6, 6.0
Select inner viewport: 0.8, 7.6, 4.6, 5.9

selectObject: finalOut
# Vibrant Teal
Colour: "{0.1, 0.7, 0.6}"
Draw: 0, 0, 0, 0, "no", "Curve"

Colour: "Black"
Draw inner box
Font size: 8
Select outer viewport: 0.15, 8, 4.6, 6.0
Text left: "yes", "Mosaic"
Text bottom: "yes", "Time (s)"

# === PANEL 4: STYLIZED DARK-MODE STATS BAR ===
Select outer viewport: 0, 8, 6.3, 6.8
Select inner viewport: 0.8, 7.6, 6.3, 6.7

Axes: 0, 1, 0, 1
# Dark slate background
Paint rectangle: "{0.15, 0.15, 0.18}", 0, 1, 0, 1
Colour: "Black"
Draw rectangle: 0, 1, 0, 1

Font size: 8
Colour: "{0.9, 0.9, 0.9}"
Text: 0.02, "left", 0.5, "half", "GRAIN: " + string$(grain_size_ms) + "ms   |   OVERLAP: " + fixed$(overlap_ratio * 100, 0) + "%"

# Colored weights info
Colour: "{0.5, 0.8, 0.9}"
Text: 0.50, "centre", 0.5, "half", "Weights [ Pitch: " + fixed$(pitch_weight, 1) + " | Spectral: " + fixed$(spectral_weight, 1) + " ]"

Colour: "{0.9, 0.9, 0.9}"
Text: 0.98, "right", 0.5, "half", "GRAINS MAPPED: " + string$(nTarget)

# Reset for safety
Font size: 10
Colour: "Black"
Line width: 1

# ============================================
# CLEANUP
# ============================================

removeObject: targetSnd, sourceSnd

selectObject: id1
plusObject: id2
plusObject: finalOut

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: finalOut
n_ch = Get number of channels
out_dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(out_dur, 2), " s"
appendInfoLine: "Channels: ", n_ch

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut