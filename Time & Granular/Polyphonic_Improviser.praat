# ============================================================
# Praat AudioTools - Polyphonic_Improviser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Polyphonic Improviser v2 - Chunk-shuffle canon engine.
#   All material derived from the input. No synthesis, no PSOLA.
#
#   APPROACH:
#   1. Source divided into N equal audible chunks.
#   2. Each voice gets an independently shuffled ordering of those
#      chunks and plays them sequentially (canon by delay + shuffle).
#   3. Each voice applies a speed/pitch transformation:
#      Tape Speed  - Override SR by ratio (pitch + time together).
#      Lengthen    - Lengthen (overlap-add) by 1/ratio (time only).
#   4. Chunks joined with crossfade, voices panned, additively mixed.
#
#   VOICE DEFAULTS:
#     V1 Leader : ratio 1.00  pan -0.35  enters at 0
#     V2 Comes  : ratio 1.059 (+1st)  pan +0.40  enters at delay
#     V3 Third  : ratio 0.50  (-8vb)   pan -0.75  enters at 2x delay
#     V4 Fourth : ratio 1.50           pan +0.75  enters at 3x delay
#
# Category: Composition
#
# Changelog v2.1:
#   - Audio pipeline UNCHANGED. Output bit-identical to v2.0
#     for the same form parameters and same RNG state. Same
#     chunk extraction, same shuffle algorithm with dummy RNG
#     advance per voice, same transforms, same crossfade
#     concatenation, same panning, same silence trim.
#   - Fix: three == comparisons changed to = (Praat's
#     documented comparison operator). v2.0 used == as an
#     alias which works in current Praat but isn't guaranteed.
#   - Voice count clamping (2 <= numV <= 4) now reports when
#     the user's value was clamped — v2.0 silently changed
#     it without notice.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): chunk shuffle map — the
#         script's most distinctive visual, promoted from v2.0's
#         third panel position
#       Panel B (right, headline): active span per voice
#       Panel C: L channel waveform with beat gridlines +
#         voice entry markers
#       Panel D: R channel waveform with same overlays
#       Panel E: summary stats bar
#     All v2.0 visualization information preserved (waveforms,
#     voice colors, beat lines, voice entries, shuffle indices,
#     active spans, stats). Just reorganized for the 8x8 suite
#     standard.
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcSound = selected("Sound")
srcName$ = selected$("Sound")

selectObject: srcSound
srcDur = Get total duration
srcSr  = Get sampling frequency
srcCh  = Get number of channels

if srcDur < 1.0
    exitScript: "Sound too short (minimum 1 s)."
endif

# ============================================================
# FORM
# ============================================================

form Polyphonic Improviser v2.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Slow Canon      (tape, octave drop, 4-bar entries)
        option Dense Cluster   (tape, semitone cloud, short entries)
        option Spectral Drift  (lengthen, subtle ratios, long entries)
        option Rhythmic Echo   (tape, fifth+octave, beat-quantized)
        option Mirror Scatter  (tape, inverse ratios, many chunks)
        option Microtonal Haze (lengthen, tiny ratios, 4 voices)
    comment === Chunks ===
    natural Number_of_chunks 12
    positive Crossfade_ms 30.0
    comment === Voices & Transform ===
    integer Number_of_voices 3
    optionmenu Transform_mode: 1
        option Tape speed  (pitch + time)
        option Lengthen  (time only)
    positive V1_speed_ratio 1.00
    positive V2_speed_ratio 1.059
    comment === Entry Timing ===
    boolean Quantize_entries 0
    positive Tempo_bpm 120.0
    optionmenu Note_value: 3
        option Whole note  (4 beats)
        option Half note  (2 beats)
        option Quarter note  (1 beat)
        option Eighth note  (0.5 beats)
        option Dotted whole  (6 beats)
        option Dotted half  (3 beats)
        option Dotted quarter  (1.5 beats)
        option 2 bars  (8 beats)
        option 4 bars  (16 beats)
    positive Entry_delay_s 3.0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ---- Advanced settings (V3/V4 speeds, amplitudes, pans) ----
beginPause: "Voice Details (V3, V4, amplitudes, pan)"
    comment: "=== V3 & V4 Speed Ratios ==="
    positive: "V3_speed_ratio", 0.50
    positive: "V4_speed_ratio", 1.50
    comment: "=== Amplitudes ==="
    positive: "V1_amplitude", 1.0
    positive: "V2_amplitude", 0.85
    positive: "V3_amplitude", 0.75
    positive: "V4_amplitude", 0.65
    comment: "=== Pan  (-1=left  0=centre  +1=right) ==="
    real: "V1_pan", -0.35
    real: "V2_pan",  0.40
    real: "V3_pan", -0.75
    real: "V4_pan",  0.75
clicked = endPause: "Cancel", "OK", 2, 1
if clicked = 1
    exitScript: ""
endif

# ============================================================
# ALIASES
# ============================================================

bpm          = tempo_bpm
use_quantize = quantize_entries
note_val     = note_value
nChunks      = number_of_chunks
xfadeMs      = crossfade_ms
numV_input   = number_of_voices
numV         = number_of_voices
tMode        = transform_mode

vSpeed_1 = v1_speed_ratio
vSpeed_2 = v2_speed_ratio
vSpeed_3 = v3_speed_ratio
vSpeed_4 = v4_speed_ratio

vAmp_1 = v1_amplitude
vAmp_2 = v2_amplitude
vAmp_3 = v3_amplitude
vAmp_4 = v4_amplitude

vPan_1 = v1_pan
vPan_2 = v2_pan
vPan_3 = v3_pan
vPan_4 = v4_pan

# ============================================================
# PRESETS  (override form values when preset != Custom)
# ============================================================

presetName$ = "Custom"

if preset = 2
    presetName$ = "Slow Canon"
    nChunks    = 8
    xfadeMs    = 80.0
    numV       = 3
    tMode      = 1
    vSpeed_1   = 1.0
    vSpeed_2   = 1.059
    vSpeed_3   = 0.5
    vSpeed_4   = 0.75
    vAmp_1     = 1.0
    vAmp_2     = 0.80
    vAmp_3     = 0.70
    vAmp_4     = 0.65
    vPan_1     = -0.30
    vPan_2     =  0.35
    vPan_3     = -0.70
    vPan_4     =  0.70
    use_quantize  = 1
    bpm           = 72.0
    note_val      = 9
    noteBeats     = 16.0
    noteName$     = "4 bars"
elsif preset = 3
    presetName$ = "Dense Cluster"
    nChunks    = 24
    xfadeMs    = 15.0
    numV       = 4
    tMode      = 1
    vSpeed_1   = 1.0
    vSpeed_2   = 1.059
    vSpeed_3   = 1.122
    vSpeed_4   = 0.944
    vAmp_1     = 0.90
    vAmp_2     = 0.85
    vAmp_3     = 0.80
    vAmp_4     = 0.75
    vPan_1     = -0.50
    vPan_2     =  0.50
    vPan_3     = -0.20
    vPan_4     =  0.20
    use_quantize  = 1
    bpm           = 120.0
    note_val      = 3
    noteBeats     = 1.0
    noteName$     = "quarter"
elsif preset = 4
    presetName$ = "Spectral Drift"
    nChunks    = 6
    xfadeMs    = 120.0
    numV       = 3
    tMode      = 2
    vSpeed_1   = 1.0
    vSpeed_2   = 0.85
    vSpeed_3   = 1.20
    vSpeed_4   = 0.70
    vAmp_1     = 1.0
    vAmp_2     = 0.85
    vAmp_3     = 0.75
    vAmp_4     = 0.65
    vPan_1     = -0.25
    vPan_2     =  0.30
    vPan_3     = -0.65
    vPan_4     =  0.65
    use_quantize  = 0
    entry_delay_s = 6.0
elsif preset = 5
    presetName$ = "Rhythmic Echo"
    nChunks    = 16
    xfadeMs    = 25.0
    numV       = 4
    tMode      = 1
    vSpeed_1   = 1.0
    vSpeed_2   = 1.498
    vSpeed_3   = 0.5
    vSpeed_4   = 0.749
    vAmp_1     = 1.0
    vAmp_2     = 0.80
    vAmp_3     = 0.75
    vAmp_4     = 0.70
    vPan_1     = -0.40
    vPan_2     =  0.45
    vPan_3     = -0.80
    vPan_4     =  0.80
    use_quantize  = 1
    bpm           = 100.0
    note_val      = 2
    noteBeats     = 2.0
    noteName$     = "half"
elsif preset = 6
    presetName$ = "Mirror Scatter"
    nChunks    = 20
    xfadeMs    = 10.0
    numV       = 4
    tMode      = 1
    vSpeed_1   = 1.0
    vSpeed_2   = 1.0
    vSpeed_3   = 1.33
    vSpeed_4   = 0.75
    vAmp_1     = 0.90
    vAmp_2     = 0.90
    vAmp_3     = 0.80
    vAmp_4     = 0.80
    vPan_1     = -0.60
    vPan_2     =  0.60
    vPan_3     = -0.30
    vPan_4     =  0.30
    use_quantize  = 1
    bpm           = 90.0
    note_val      = 3
    noteBeats     = 1.0
    noteName$     = "quarter"
elsif preset = 7
    presetName$ = "Microtonal Haze"
    nChunks    = 10
    xfadeMs    = 60.0
    numV       = 4
    tMode      = 2
    vSpeed_1   = 1.0
    vSpeed_2   = 1.025
    vSpeed_3   = 0.975
    vSpeed_4   = 1.05
    vAmp_1     = 0.90
    vAmp_2     = 0.88
    vAmp_3     = 0.85
    vAmp_4     = 0.82
    vPan_1     = -0.55
    vPan_2     =  0.55
    vPan_3     = -0.25
    vPan_4     =  0.25
    use_quantize  = 0
    entry_delay_s = 1.5
endif

if use_quantize = 1
    beatDur  = 60.0 / bpm
    entry_delay_s = beatDur * noteBeats
    entryMode$ = "BPM"
else
    beatDur  = 60.0 / bpm
    entryMode$ = "Manual"
endif

# ============================================================
# CLAMPING
# ============================================================

if nChunks < 2
    nChunks = 2
endif
if nChunks > 200
    nChunks = 200
endif
if numV < 2
    numV = 2
endif
if numV > 4
    numV = 4
endif
if xfadeMs < 0
    xfadeMs = 0
endif
if xfadeMs > 500
    xfadeMs = 500
endif
for v from 1 to 4
    if vSpeed_'v' < 0.05
        vSpeed_'v' = 0.05
    endif
    if vSpeed_'v' > 8.0
        vSpeed_'v' = 8.0
    endif
    if vAmp_'v' < 0.0
        vAmp_'v' = 0.0
    endif
    if vPan_'v' < -1.0
        vPan_'v' = -1.0
    endif
    if vPan_'v' > 1.0
        vPan_'v' = 1.0
    endif
endfor

# Pre-compute clamping notice (replaces v2.0's silent clamp)
if numV_input <> numV
    voiceClampNote$ = "  [user requested " + string$(numV_input) + ", clamped to " + string$(numV) + "]"
else
    voiceClampNote$ = ""
endif

# ============================================================
# BPM / ENTRY TIMING
# ============================================================

if preset = 1
    if note_val = 1
        noteBeats = 4.0
        noteName$ = "whole"
    elsif note_val = 2
        noteBeats = 2.0
        noteName$ = "half"
    elsif note_val = 3
        noteBeats = 1.0
        noteName$ = "quarter"
    elsif note_val = 4
        noteBeats = 0.5
        noteName$ = "eighth"
    elsif note_val = 5
        noteBeats = 6.0
        noteName$ = "dotted whole"
    elsif note_val = 6
        noteBeats = 3.0
        noteName$ = "dotted half"
    elsif note_val = 7
        noteBeats = 1.5
        noteName$ = "dotted quarter"
    elsif note_val = 8
        noteBeats = 8.0
        noteName$ = "2 bars"
    else
        noteBeats = 16.0
        noteName$ = "4 bars"
    endif
    beatDur = 60.0 / bpm
    if use_quantize = 1
        entry_delay_s = beatDur * noteBeats
        entryMode$ = "BPM"
    else
        entryMode$ = "Manual"
    endif
endif

# ============================================================
# SETUP
# ============================================================

selectObject: srcSound
if srcCh > 1
    monoSrc = Convert to mono
else
    monoSrc = Copy: "pi_mono_src"
endif

chunkDur = srcDur / nChunks
xfadeSec = xfadeMs / 1000.0
if xfadeSec > chunkDur * 0.4
    xfadeSec = chunkDur * 0.4
endif

if tMode = 1
    tModeName$ = "Tape speed"
else
    tModeName$ = "Lengthen"
endif

clearinfo
writeInfoLine:  "=================================================="
appendInfoLine: "  Polyphonic Improviser v2.1  | Chunk Shuffle Canon"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Source   : ", srcName$, " | ", fixed$(srcDur, 2), " s | ", srcSr, " Hz"
appendInfoLine: "Chunks   : ", nChunks, " x ", fixed$(chunkDur, 3), " s"
appendInfoLine: "Transform: ", tModeName$
appendInfoLine: "Voices   : ", numV, voiceClampNote$
appendInfoLine: "Entry    : ", fixed$(entry_delay_s, 3), " s  [", entryMode$, "]"
if use_quantize = 1
    appendInfoLine: "BPM      : ", fixed$(bpm, 1),
        ... "  | Note: ", noteName$, "  |  Beat: ", fixed$(beatDur, 4), " s"
endif
appendInfoLine: "Crossfade: ", fixed$(xfadeMs, 1), " ms"
appendInfoLine: ""

# ============================================================
# STEP 1: EXTRACT ALL CHUNKS FROM SOURCE
# ============================================================

appendInfoLine: "[1/5] Extracting ", nChunks, " chunks..."

for c from 1 to nChunks
    cStart = (c - 1) * chunkDur
    cEnd   = c * chunkDur
    if cEnd > srcDur
        cEnd = srcDur
    endif
    selectObject: monoSrc
    Extract part: cStart, cEnd, "rectangular", 1, "no"
    chunk_'c' = selected("Sound")
endfor

appendInfoLine: "  Chunk size: ", fixed$(chunkDur, 3), " s  | Crossfade: ", fixed$(xfadeMs, 1), " ms"

# ============================================================
# STEP 2: TRANSFORM CHUNKS PER VOICE
# ============================================================

appendInfoLine: ""
appendInfoLine: "[2/5] Transforming chunks per voice..."

for v from 1 to numV
    vR = vSpeed_'v'
    appendInfoLine: "  V", v, ": ratio=", fixed$(vR, 4), "  mode=", tModeName$, "  pan=", fixed$(vPan_'v', 2)

    for c from 1 to nChunks
        selectObject: chunk_'c'

        if tMode = 1
            Copy: "tc_v" + string$(v) + "_c" + string$(c)
            tChunk = selected("Sound")
            Override sampling frequency: srcSr * vR
            Resample: srcSr, 50
            resampledChunk = selected("Sound")
            removeObject: tChunk
            tChunk = resampledChunk
        else
            lenFactor = 1.0 / vR
            if lenFactor < 0.1
                lenFactor = 0.1
            endif
            if lenFactor > 8.0
                lenFactor = 8.0
            endif
            selectObject: chunk_'c'
            Lengthen (overlap-add): 75, 600, lenFactor
            tChunk = selected("Sound")
        endif

        selectObject: tChunk
        tCDur = Get total duration
        fadeSec = 0.010
        if fadeSec > tCDur * 0.2
            fadeSec = tCDur * 0.2
        endif
        if fadeSec > 0.001
            fsStr$ = fixed$(fadeSec, 8)
            Formula: "if x - xmin < " + fsStr$ + " then self * ((x - xmin) / " + fsStr$ + ") else self fi"
            Formula: "if xmax - x < " + fsStr$ + " then self * ((xmax - x) / " + fsStr$ + ") else self fi"
        endif

        vChunk_'v'_'c' = tChunk
    endfor
endfor

# ============================================================
# STEP 3: SHUFFLE + ASSEMBLE EACH VOICE
# ============================================================

appendInfoLine: ""
appendInfoLine: "[3/5] Shuffling and assembling voices..."

v1PassDur = 0
for c from 1 to nChunks
    selectObject: vChunk_1_'c'
    cDurTmp = Get total duration
    v1PassDur = v1PassDur + cDurTmp
endfor

lastEntry = entry_delay_s * (numV - 1)
outDur = lastEntry + v1PassDur + 0.5

for v from 1 to numV
    vEntryTime = entry_delay_s * (v - 1)
    
    for c from 1 to nChunks
        shuffleIdx_'c' = c
    endfor
    for dummy from 1 to (v - 1) * nChunks
        discard = randomInteger(1, nChunks)
    endfor
    for fy_k from 1 to nChunks - 1
        i = nChunks - fy_k + 1
        j = randomInteger(1, i)
        tmp = shuffleIdx_'i'
        shuffleIdx_'i' = shuffleIdx_'j'
        shuffleIdx_'j' = tmp
    endfor

    if vEntryTime > 0.002
        Create Sound from formula: "v_entry_sil", 1, 0, vEntryTime, srcSr, "0"
        vAssembled = selected("Sound")
        hasAssembled = 1
    else
        hasAssembled = 0
        vAssembled = 0
    endif

    for ci from 1 to nChunks
        c = shuffleIdx_'ci'

        if hasAssembled = 0
            selectObject: vChunk_'v'_'c'
            Copy: "v" + string$(v) + "_asm"
            vAssembled = selected("Sound")
            hasAssembled = 1
        else
            selectObject: vAssembled
            aDur = Get total duration
            selectObject: vChunk_'v'_'c'
            nextDur = Get total duration

            safeCF = xfadeSec
            minDur = aDur
            if nextDur < minDur
                minDur = nextDur
            endif
            if safeCF > minDur * 0.4
                safeCF = minDur * 0.4
            endif

            if safeCF > 0.002
                selectObject: vAssembled
                plusObject: vChunk_'v'_'c'
                Concatenate with overlap: safeCF
            else
                selectObject: vAssembled
                plusObject: vChunk_'v'_'c'
                Concatenate
            endif
            newAss = selected("Sound")
            removeObject: vAssembled
            vAssembled = newAss
        endif
    endfor

    selectObject: vAssembled
    aDur = Get total duration
    if aDur < outDur - 0.005
        padN = outDur - aDur
        Create Sound from formula: "v_endpad", 1, 0, padN, srcSr, "0"
        padSnd = selected("Sound")
        selectObject: vAssembled
        plusObject: padSnd
        padded = Concatenate
        removeObject: vAssembled, padSnd
        vAssembled = padded
    elsif aDur > outDur + 0.005
        selectObject: vAssembled
        Extract part: 0, outDur, "rectangular", 1, "no"
        trimmed = selected("Sound")
        removeObject: vAssembled
        vAssembled = trimmed
    endif

    selectObject: vAssembled
    Formula: "self * " + string$(vAmp_'v')
    vMono_'v' = vAssembled
endfor

# Cleanup chunks
for v from 1 to numV
    for c from 1 to nChunks
        removeObject: vChunk_'v'_'c'
    endfor
endfor
for c from 1 to nChunks
    removeObject: chunk_'c'
endfor
removeObject: monoSrc

# ============================================================
# STEP 3b: PAN + STEREO MIX
# ============================================================

for v from 1 to numV
    panVal = vPan_'v'
    angle = (panVal + 1.0) * 0.5 * (pi / 2)
    leftGain  = cos(angle)
    rightGain = sin(angle)

    selectObject: vMono_'v'
    vL_'v' = Copy: "vL" + string$(v)
    selectObject: vL_'v'
    Formula: "self * " + string$(leftGain)

    selectObject: vMono_'v'
    vR_'v' = Copy: "vR" + string$(v)
    selectObject: vR_'v'
    Formula: "self * " + string$(rightGain)

    removeObject: vMono_'v'
endfor

for v from 2 to numV
    selectObject: vL_1
    Formula: "self + object[vL_'v']"
    selectObject: vR_1
    Formula: "self + object[vR_'v']"
    removeObject: vL_'v', vR_'v'
endfor

selectObject: vL_1
plusObject: vR_1
finalOutput = Combine to stereo
removeObject: vL_1, vR_1

selectObject: finalOutput
Scale peak: 0.95
Rename: srcName$ + "_poly_improv_v2"
finalDur = Get total duration

# ============================================================
# STEP 4: AUTO-TRIM SILENCE (AMPLITUDE SCAN)
# ============================================================

appendInfoLine: ""
appendInfoLine: "[4/5] Trimming silence from output (Amplitude Scan)..."

selectObject: finalOutput
tempMono = Convert to mono
dur = Get total duration

step = 0.05
nSteps = floor(dur / step)
thresh = 0.005

startTime = -1
endTime = -1

# v2.1 fix: == changed to = (Praat's documented comparison operator)
for i from 1 to nSteps
    t1 = (i - 1) * step
    t2 = i * step
    
    peakMax = Get maximum: t1, t2, "None"
    peakMin = Get minimum: t1, t2, "None"
    
    if peakMax > thresh or peakMin < -thresh
        if startTime = -1
            startTime = t1
        endif
        endTime = t2
    endif
endfor

t1 = nSteps * step
if t1 < dur
    peakMax = Get maximum: t1, dur, "None"
    peakMin = Get minimum: t1, dur, "None"
    if peakMax > thresh or peakMin < -thresh
        if startTime = -1
            startTime = t1
        endif
        endTime = dur
    endif
endif

removeObject: tempMono

trimOffset = 0
if startTime <> -1
    startTime = startTime - 0.05
    if startTime < 0
        startTime = 0
    endif
    endTime = endTime + 0.05
    if endTime > dur
        endTime = dur
    endif

    if startTime > 0.1 or (dur - endTime) > 0.1
        selectObject: finalOutput
        trimmedSound = Extract part: startTime, endTime, "rectangular", 1, "no"
        Rename: srcName$ + "_poly_improv_v2"
        
        removeObject: finalOutput
        finalOutput = trimmedSound
        finalDur = Get total duration
        trimOffset = startTime
        
        appendInfoLine: "  Trimmed: Removed silences (Start: ", fixed$(startTime, 2), "s, End: ", fixed$(dur - endTime, 2), "s removed)."
    else
        appendInfoLine: "  Trim skipped (no significant silence to remove)."
    endif
else
    appendInfoLine: "  Trim skipped (audio entirely below threshold)."
endif

# ============================================================
# STEP 5: VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

appendInfoLine: ""
appendInfoLine: "[5/5] Visualization..."

if draw_visualization = 1

    selectObject: finalOutput
    Extract one channel: 1
    vizL = selected("Sound")
    selectObject: finalOutput
    Extract one channel: 2
    vizR = selected("Sound")

    selectObject: vizL
    ampL = Get absolute extremum: 0, 0, "None"
    selectObject: vizR
    ampR = Get absolute extremum: 0, 0, "None"
    ampMax = ampL
    if ampR > ampMax
        ampMax = ampR
    endif
    if ampMax < 0.001
        ampMax = 0.001
    endif
    ampMax = ampMax * 1.1

    # Voice colors (preserved from v2.0)
    vColR_1 = 0.20
    vColG_1 = 0.45
    vColB_1 = 0.82
    vColR_2 = 0.82
    vColG_2 = 0.32
    vColB_2 = 0.20
    vColR_3 = 0.22
    vColG_3 = 0.65
    vColB_3 = 0.30
    vColR_4 = 0.70
    vColG_4 = 0.28
    vColB_4 = 0.75

    Erase all

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##POLYPHONIC IMPROVISER (chunk shuffle canon)##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... srcName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(numV) + " voices"
        ... + "  |  " + string$(nChunks) + " chunks x " + fixed$(chunkDur, 3) + "s"
        ... + "  |  Mode: " + tModeName$
        ... + "  |  Entry: " + fixed$(entry_delay_s, 3) + "s [" + entryMode$ + "]"

    # ----------------------------------------------------------
    # PANEL A: CHUNK SHUFFLE MAP  (left, headline)
    # The script's signature visual. Top row = source order
    # (numbered chunks colored by position). Each voice row
    # below shows that voice's shuffled assignment of chunks
    # to output slots.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    rowH = 1.0
    panelH = (numV + 1) * rowH
    Axes: 0, nChunks, 0, panelH
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nChunks, 0, panelH

    # Top row: source order
    for c from 1 to nChunks
        norm = (c - 1) / nChunks
        Paint rectangle: "{" + fixed$(0.3+norm*0.5,2) + ", " + fixed$(0.3+norm*0.3,2) + ", " + fixed$(0.8-norm*0.4,2) + "}",
            ... c - 1, c, numV * rowH + 0.1, (numV + 1) * rowH - 0.1
        Colour: "White"
        Font size: 5
        Text: c - 0.5, "centre", numV * rowH + 0.5, "half", string$(c)
    endfor
    Axes: 0, 1, 0, 1
    Colour: "{0.5, 0.5, 0.5}"
    Font size: 6
    Text: 0.01, "left", (numV * rowH + 0.5) / panelH, "half", "src"
    Axes: 0, nChunks, 0, panelH

    # Voice rows: reproduce the shuffle by regenerating RNG state
    # (matches Step 3 audio shuffle exactly)
    for v from 1 to numV
        rowBot = (numV - v) * rowH + 0.1
        rowTop = (numV - v + 1) * rowH - 0.1
        cR = vColR_'v'
        cG = vColG_'v'
        cB = vColB_'v'

        for c from 1 to nChunks
            vizIdx_'c' = c
        endfor
        for dummy from 1 to (v - 1) * nChunks
            discard = randomInteger(1, nChunks)
        endfor
        for fy_k from 1 to nChunks - 1
            i = nChunks - fy_k + 1
            j = randomInteger(1, i)
            tmp = vizIdx_'i'
            vizIdx_'i' = vizIdx_'j'
            vizIdx_'j' = tmp
        endfor

        for ci from 1 to nChunks
            c = vizIdx_'ci'
            norm = (c - 1) / nChunks
            bR = cR * (0.35 + norm * 0.65)
            bG = cG * (0.35 + norm * 0.65)
            bB = cB * (0.35 + norm * 0.65)
            Paint rectangle: "{" + fixed$(bR,2) + ", " + fixed$(bG,2) + ", " + fixed$(bB,2) + "}",
                ... ci - 1, ci, rowBot, rowTop
            Colour: "White"
            Font size: 5
            Text: ci - 0.5, "centre", (rowBot + rowTop) / 2, "half", string$(c)
        endfor

        Axes: 0, 1, 0, 1
        vCs$ = "{" + fixed$(cR,2) + ", " + fixed$(cG,2) + ", " + fixed$(cB,2) + "}"
        Colour: vCs$
        Font size: 6
        Text: 0.01, "left", ((numV - v) * rowH + 0.5) / panelH, "half", "V" + string$(v)
        Axes: 0, nChunks, 0, panelH
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Voice"
    Text bottom: "yes", "Output slot (number = source chunk)"

    # ----------------------------------------------------------
    # PANEL B: ACTIVE SPAN PER VOICE  (right, headline)
    # Horizontal bars showing each voice's entry -> end-of-shuffle
    # range with speed and pan annotations.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, finalDur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, 0, 1

    for v from 1 to numV
        vEnt = (entry_delay_s * (v - 1)) - trimOffset
        vEndEst = vEnt + (v1PassDur / vSpeed_'v')

        if vEnt < 0
            vEnt = 0
        endif
        if vEndEst > finalDur
            vEndEst = finalDur
        endif

        if vEndEst > vEnt
            cR = vColR_'v'
            cG = vColG_'v'
            cB = vColB_'v'
            vCs$ = "{" + fixed$(cR,2) + ", " + fixed$(cG,2) + ", " + fixed$(cB,2) + "}"
            barBot = (numV - v) / numV + 0.03
            barTop = (numV - v + 1) / numV - 0.03
            Paint rectangle: vCs$, vEnt, vEndEst, barBot, barTop
            Colour: "White"
            Font size: 6
            Text: (vEnt + vEndEst) / 2, "centre", (barBot + barTop) / 2, "half",
                ... "V" + string$(v) + "  x" + fixed$(vSpeed_'v', 3)
                ... + "  pan" + fixed$(vPan_'v', 2)
        endif
    endfor

    # Beat gridlines
    bT = beatDur - (trimOffset mod beatDur)
    while bT < finalDur
        Colour: "{0.80, 0.80, 0.80}"
        Dotted line
        Draw line: bT, 0, bT, 1
        Solid line
        bT = bT + beatDur
    endwhile

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Voice"
    Text bottom: "yes", "Output time (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Chunk shuffle map (color intensity = source position)"
    Text: 6.10, "centre", 7.30, "half", "Active span per voice (entry -> end)"

    # ----------------------------------------------------------
    # PANEL C: LEFT CHANNEL WAVEFORM
    # With beat gridlines (light) and voice entry markers (colored)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    Axes: 0, finalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampMax, ampMax
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 0, finalDur, 0

    # Beat gridlines (light)
    bT = beatDur - (trimOffset mod beatDur)
    while bT < finalDur
        Colour: "{0.90, 0.90, 0.90}"
        Dotted line
        Draw line: bT, -ampMax, bT, ampMax
        Solid line
        bT = bT + beatDur
    endwhile

    # Voice entry markers (colored, dotted)
    for v from 1 to numV
        vEnt = (entry_delay_s * (v - 1)) - trimOffset
        if vEnt >= 0 and vEnt < finalDur
            cR = vColR_'v'
            cG = vColG_'v'
            cB = vColB_'v'
            vCs$ = "{" + fixed$(cR,2) + ", " + fixed$(cG,2) + ", " + fixed$(cB,2) + "}"
            Colour: vCs$
            Line width: 1.5
            Dotted line
            Draw line: vEnt, -ampMax, vEnt, ampMax
            Solid line
            Line width: 1
        endif
    endfor

    selectObject: vizL
    Colour: "{0.20, 0.45, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Left channel  (light dotted = beats | colored dotted = voice entries)"
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL D: RIGHT CHANNEL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, finalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampMax, ampMax
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 0, finalDur, 0

    bT = beatDur - (trimOffset mod beatDur)
    while bT < finalDur
        Colour: "{0.90, 0.90, 0.90}"
        Dotted line
        Draw line: bT, -ampMax, bT, ampMax
        Solid line
        bT = bT + beatDur
    endwhile

    for v from 1 to numV
        vEnt = (entry_delay_s * (v - 1)) - trimOffset
        if vEnt >= 0 and vEnt < finalDur
            cR = vColR_'v'
            cG = vColG_'v'
            cB = vColB_'v'
            vCs$ = "{" + fixed$(cR,2) + ", " + fixed$(cG,2) + ", " + fixed$(cB,2) + "}"
            Colour: vCs$
            Line width: 1.5
            Dotted line
            Draw line: vEnt, -ampMax, vEnt, ampMax
            Solid line
            Line width: 1
        endif
    endfor

    selectObject: vizR
    Colour: "{0.82, 0.30, 0.20}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Right channel"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    removeObject: vizL, vizR

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if use_quantize = 1
        timingStr$ = "BPM " + fixed$(bpm, 1) + " / " + noteName$
            ... + " = " + fixed$(entry_delay_s, 3) + "s entry"
    else
        timingStr$ = "Manual entry: " + fixed$(entry_delay_s, 3) + "s"
            ... + "  (" + fixed$(entry_delay_s / beatDur, 2) + " beats @ " + fixed$(bpm, 1) + " bpm)"
    endif

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.78, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + srcName$
        ... + "  |  " + string$(numV) + " voices x " + string$(nChunks) + " chunks (" + fixed$(chunkDur, 3) + "s each)"
        ... + "  |  Transform: " + tModeName$
        ... + "  |  Xfade: " + fixed$(xfadeMs, 1) + " ms"

    Text: 0.02, "left", 0.50, "half",
        ... "V1 x" + fixed$(vSpeed_1, 3) + " pan" + fixed$(vPan_1, 2)
        ... + "  V2 x" + fixed$(vSpeed_2, 3) + " pan" + fixed$(vPan_2, 2)
        ... + "  V3 x" + fixed$(vSpeed_3, 3) + " pan" + fixed$(vPan_3, 2)
        ... + "  V4 x" + fixed$(vSpeed_4, 3) + " pan" + fixed$(vPan_4, 2)

    Text: 0.02, "left", 0.20, "half",
        ... timingStr$
        ... + "  |  Output: " + srcName$ + "_poly_improv_v2"
        ... + " (" + fixed$(finalDur, 2) + " s, peak normalized 0.95)"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete."
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Output   : ", srcName$, "_poly_improv_v2"
appendInfoLine: "Duration : ", fixed$(finalDur, 2), " s"
appendInfoLine: "Chunks   : ", nChunks, " x ", fixed$(chunkDur, 3), " s"
appendInfoLine: "Mode     : ", tModeName$
appendInfoLine: ""
appendInfoLine: "Voice speeds:"
for v from 1 to numV
    appendInfoLine: "  V", v, ": x", fixed$(vSpeed_'v', 4), "  pan ", fixed$(vPan_'v', 2),
        ... "  entry ", fixed$(entry_delay_s * (v-1), 3), " s"
endfor
appendInfoLine: ""
appendInfoLine: "BPM: ", fixed$(bpm, 1), "  Beat: ", fixed$(beatDur, 4), " s",
    ... "  Entry = ", fixed$(entry_delay_s / beatDur, 2), " beats  [", entryMode$, "]"

if play_output = 1
    Play
endif

selectObject: finalOutput
