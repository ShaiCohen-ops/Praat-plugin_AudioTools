# ============================================================
# Praat AudioTools - Messagesquisse_Opening.praat (Modified v4.4)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.4 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Boulez-inspired additive drone machine after Messagesquisse.
#   Transforms a single cello tone into a six-layer hexachordal
#   field using the SACHER pitch set and Morse-derived timing.
#
#   PITCH STRUCTURE — SACHER hexachord (Boulez, 1975):
#     S  A  C  H  E  R
#     Eb A  C  B  E  D
#     Semitone offsets from C: [3, 9, 0, 11, 4, 2]
#     Each layer pitch-shifted via Sample Rate Reinterpretation.
#
#   TEMPORAL STRUCTURE — Morse code of "SACHER":
#     S=...  A=.-  C=-.-.  H=....  E=.  R=.-.
#     Total score = 36 Morse units.
#     unit_duration auto-scaled to fill input duration.
#     Entry times are cumulative letter durations:
#       Eb at 0, A after S, C after A, B after C, E after H, D after E.
#
#   SCORE-ADVANCING SOURCE SEGMENTATION:
#     Layer i reads original[entry_i ... entry_i + active_dur_i].
#     The source material advances in sync with the score so that
#     later-entering voices emerge from a later moment in the
#     recording. Optional looping if source is shorter.
#
#   STEREO FIELD:
#     Voices distributed evenly from -pan_spread to +pan_spread
#     in entry order (Eb=leftmost, D=rightmost).
#     Constant-power pan law: L=cos(a), R=sin(a).
#     Accumulation directly into L/R mono buffers via Formula.
#
#   DRY / WET:
#     Dry = original (centred, 0.707 gain on both channels).
#     Wet = six processed pitch-shifted layers.
#     wet_mix 0→1 fades between pure original and full field.
#
#   VISUALIZATION (6 panels):
#     1. Input waveform
#     2. Output L waveform
#     3. Output R waveform
#     4. Layer accumulation timeline (entry bars, color = pan)
#     5. Stereo pan field map
#     6. SACHER pitches
#
# Category: Composition / Spectral / Pitch
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound     = selected("Sound")
soundName$        = selected$("Sound")

selectObject: originalSound
originalDuration  = Get total duration
samplingFrequency = Get sampling frequency
numChannels       = Get number of channels

if originalDuration < 1.0
    exitScript: "Sound must be at least 1 second."
endif

# --- Create a background mono copy if needed for spatialization math ---
if numChannels > 1
    selectObject: originalSound
    workSound = Convert to mono
    Rename: soundName$ + "_workMono"
else
    workSound = originalSound
endif

# Auto unit_duration: 36 Morse units fill the whole file
totalUnits = 36
auto_unit  = originalDuration / totalUnits

# ============================================================
# FORM
# ============================================================

form Messagesquisse Opening v4.4
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Boulez Reference   (C2, full spread, 80% wet)
        option Low Drone Field    (C1, full spread, 90% wet)
        option High Shimmer       (C4, full spread, 70% wet)
        option Centred Mass       (C2, no spread, 100% wet)
        option Dry Ghost          (C2, full spread, 20% wet)
        option Quartertone Haze   (C2+50ct, partial spread, 75% wet)
    comment === Pitch (MIDI note, C2=36) ===
    integer  Base_MIDI_note 36
    comment === Timing  [0 = auto-fit to input duration] ===
    real     Unit_duration_s 0.0
    comment === Entry smoothing ===
    positive Fade_duration_s 0.05
    comment === Stereo field  [0=centre  1=full L-R] ===
    real     Pan_spread 1.0
    comment === Dry / Wet  [0=dry only  1=wet only] ===
    real     Wet_mix 0.8
    comment === Source handling ===
    boolean  Loop_if_short 1
    comment === Output ===
    boolean  Draw_visualization 1
    boolean  Play_result 1
endform

# ============================================================
# PRESET OVERRIDES
# ============================================================

preset_name$ = "Custom"

if preset = 2
    preset_name$     = "Boulez Reference"
    base_MIDI_note   = 36
    unit_duration_s  = 0.0
    fade_duration_s  = 0.05
    pan_spread       = 1.0
    wet_mix          = 0.80
    loop_if_short    = 1

elsif preset = 3
    preset_name$     = "Low Drone Field"
    base_MIDI_note   = 24
    unit_duration_s  = 0.0
    fade_duration_s  = 0.08
    pan_spread       = 1.0
    wet_mix          = 0.90
    loop_if_short    = 1

elsif preset = 4
    preset_name$     = "High Shimmer"
    base_MIDI_note   = 60
    unit_duration_s  = 0.0
    fade_duration_s  = 0.03
    pan_spread       = 1.0
    wet_mix          = 0.70
    loop_if_short    = 1

elsif preset = 5
    preset_name$     = "Centred Mass"
    base_MIDI_note   = 36
    unit_duration_s  = 0.0
    fade_duration_s  = 0.05
    pan_spread       = 0.0
    wet_mix          = 1.0
    loop_if_short    = 1

elsif preset = 6
    preset_name$     = "Dry Ghost"
    base_MIDI_note   = 36
    unit_duration_s  = 0.0
    fade_duration_s  = 0.05
    pan_spread       = 1.0
    wet_mix          = 0.20
    loop_if_short    = 0

elsif preset = 7
    preset_name$     = "Quartertone Haze"
    base_MIDI_note   = 36
    unit_duration_s  = 0.0
    fade_duration_s  = 0.06
    pan_spread       = 0.65
    wet_mix          = 0.75
    loop_if_short    = 1

endif

# ============================================================
# ALIASES & DERIVED PARAMETERS
# ============================================================

midiNote   = base_MIDI_note
fadeDur    = fade_duration_s
pSpread    = pan_spread
wetMix     = wet_mix
dryMix     = 1.0 - wetMix
loopShort  = loop_if_short

# Clamp pan_spread and wet_mix to [0, 1]
if pSpread > 1.0
    pSpread = 1.0
endif
if pSpread < 0.0
    pSpread = 0.0
endif
if wetMix > 1.0
    wetMix = 1.0
endif
if wetMix < 0.0
    wetMix = 0.0
endif
dryMix = 1.0 - wetMix

# MIDI → Hz
baseFreq = 440.0 * (2 ^ ((midiNote - 69) / 12.0))

# MIDI note name (for display)
noteNames$[0]  = "C"
noteNames$[1]  = "C#"
noteNames$[2]  = "D"
noteNames$[3]  = "Eb"
noteNames$[4]  = "E"
noteNames$[5]  = "F"
noteNames$[6]  = "F#"
noteNames$[7]  = "G"
noteNames$[8]  = "Ab"
noteNames$[9]  = "A"
noteNames$[10] = "Bb"
noteNames$[11] = "B"

notePC     = midiNote mod 12
noteOctave = (midiNote div 12) - 1
noteName$  = noteNames$[notePC] + string$(noteOctave)

# Timing
if unit_duration_s <= 0.0
    dot = auto_unit
else
    dot = unit_duration_s
endif
dash = 3.0 * dot
gap  = dot

# ============================================================
# SACHER HEXACHORD
# S  A  C  H  E  R  →  Eb A C B E D
# Semitone offsets from C: [3, 9, 0, 11, 4, 2]
# ============================================================

semitones# = {3, 9, 0, 11, 4, 2}

layerName$[1] = "Layer_1_Eb"
layerName$[2] = "Layer_2_A"
layerName$[3] = "Layer_3_C"
layerName$[4] = "Layer_4_B"
layerName$[5] = "Layer_5_E"
layerName$[6] = "Layer_6_D"

pitchName$[1] = "Eb"
pitchName$[2] = "A"
pitchName$[3] = "C"
pitchName$[4] = "B"
pitchName$[5] = "E"
pitchName$[6] = "D"

for i from 1 to 6
    targetFreq[i] = baseFreq * (2 ^ (semitones#[i] / 12.0))
endfor

# ============================================================
# MORSE TIMING
# S=...  A=.-  C=-.-.  H=....  E=.  R=.-.
# ============================================================

dur_S = dot + gap + dot + gap + dot
dur_A = dot + gap + dash
dur_C = dash + gap + dot + gap + dash + gap + dot
dur_H = dot + gap + dot + gap + dot + gap + dot
dur_E = dot
dur_R = dot + gap + dash + gap + dot

entry[1] = 0
entry[2] = entry[1] + dur_S
entry[3] = entry[2] + dur_A
entry[4] = entry[3] + dur_C
entry[5] = entry[4] + dur_H
entry[6] = entry[5] + dur_E

totalDuration = entry[6] + dur_R

for i from 1 to 6
    activeDur[i] = totalDuration - entry[i]
endfor

# ============================================================
# STEREO PAN POSITIONS (constant-power law)
# ============================================================

for i from 1 to 6
    panPos[i]    = -pSpread + (i - 1) * (2.0 * pSpread / 5.0)
    panAngle     = (panPos[i] + 1.0) / 4.0 * pi
    panGainL[i]  = cos(panAngle)
    panGainR[i]  = sin(panAngle)
endfor

# ============================================================
# REPORT
# ============================================================

clearinfo
appendInfoLine: "==================================================="
appendInfoLine: "  Messagesquisse Opening v4.4"
appendInfoLine: "==================================================="
appendInfoLine: "Source   : ", soundName$, "  (", fixed$(originalDuration, 3), " s)"
appendInfoLine: "Base note: MIDI ", midiNote, "  (", noteName$, " = ", fixed$(baseFreq, 2), " Hz)"
appendInfoLine: "dot=", fixed$(dot, 4), " s   dash=", fixed$(dash, 4), " s"
appendInfoLine: "Score dur: ", fixed$(totalDuration, 4), " s"
appendInfoLine: "Wet mix  : ", fixed$(wetMix * 100, 1), "%   Pan spread: ", fixed$(pSpread * 100, 1), "%"
appendInfoLine: "Preset   : ", preset_name$
appendInfoLine: ""
appendInfoLine: "Layer     | Note | Freq (Hz)  | Entry (s)  | Active (s) | Pan   "
appendInfoLine: "----------|------|------------|------------|------------|-------"
for i from 1 to 6
    appendInfoLine: layerName$[i], " | ", pitchName$[i],
    ... "    | ", fixed$(targetFreq[i], 2),
    ... "      | ", fixed$(entry[i], 3),
    ... "      | ", fixed$(activeDur[i], 3),
    ... "      | ", fixed$(panPos[i], 2)
endfor
appendInfoLine: ""

# ============================================================
# CREATE STEREO ACCUMULATOR BUFFERS
# ============================================================

Create Sound from formula: "AccumL", 1, 0, totalDuration, samplingFrequency, "0"
accumL = selected("Sound")

Create Sound from formula: "AccumR", 1, 0, totalDuration, samplingFrequency, "0"
accumR = selected("Sound")

# ============================================================
# LAYER GENERATION LOOP
# ============================================================

for i from 1 to 6

    # 1. Calculate pitch factor (ratio of target to base)
    pf = targetFreq[i] / baseFreq
    
    # 2. Since sample rate scaling alters duration, extract a segment 
    # proportional to the pitch factor so the final shifted duration is correct
    reqDur = activeDur[i] * pf

    srcStart  = entry[i]
    srcEnd    = srcStart + reqDur
    needsLoop = 0

    if srcStart >= originalDuration
        srcStart = originalDuration - 0.01
        if srcStart < 0
            srcStart = 0
        endif
    endif

    if srcEnd > originalDuration
        needsLoop = 1
        srcEnd    = originalDuration
    endif

    # --- Extract source segment ---
    selectObject: workSound
    Extract part: srcStart, srcEnd, "Hanning", 1, "yes"
    srcSegment = selected("Sound")
    Rename: "SrcSeg_" + string$(i)

    segDur    = srcEnd - srcStart
    remainingNeeded = reqDur - segDur

    # --- Loop or pad if source overruns ---
    if needsLoop = 1 and remainingNeeded > 0.001

        if loopShort = 1
            nCopies  = ceiling(reqDur / segDur) + 1
            
            selectObject: srcSegment
            Copy: "LoopBase"
            loopBase = selected("Sound")
            
            for c from 2 to nCopies
                selectObject: loopBase
                plusObject: srcSegment
                Concatenate
                newLoop = selected("Sound")
                removeObject: loopBase
                loopBase = newLoop
            endfor
            
            selectObject: loopBase
            Extract part: 0, reqDur, "rectangular", 1, "yes"
            sourceReady = selected("Sound")
            Rename: "SourceReady_" + string$(i)
            removeObject: loopBase
            removeObject: srcSegment
        else
            Create Sound from formula: "SilPad_" + string$(i), 1,
            ... 0, remainingNeeded, samplingFrequency, "0"
            silPad = selected("Sound")
            selectObject: srcSegment
            plusObject: silPad
            Concatenate
            sourceReady = selected("Sound")
            Rename: "SourceReady_" + string$(i)
            removeObject: silPad
            removeObject: srcSegment
        endif

    else
        selectObject: srcSegment
        currentSegDur = Get total duration
        if currentSegDur > reqDur + 0.001
            Extract part: 0, reqDur, "rectangular", 1, "yes"
            sourceReady = selected("Sound")
            Rename: "SourceReady_" + string$(i)
            removeObject: srcSegment
        else
            sourceReady = srcSegment
            selectObject: sourceReady
            Rename: "SourceReady_" + string$(i)
        endif
    endif

    # --- Pitch shift via Sample Rate Reinterpretation (from Undertone_Field) ---
    oSr = round(samplingFrequency * pf)

    selectObject: sourceReady
    Override sampling frequency: oSr
    shiftedLayerRaw = Resample: samplingFrequency, 50
    removeObject: sourceReady

    # Trim or pad to exact activeDur[i] to ensure alignment
    selectObject: shiftedLayerRaw
    resampledDur = Get total duration
    if resampledDur > activeDur[i] + 0.001
        shiftedLayer = Extract part: 0, activeDur[i], "rectangular", 1, "no"
        Rename: "Shifted_" + string$(i)
        removeObject: shiftedLayerRaw
    elsif resampledDur < activeDur[i] - 0.001
        padDur = activeDur[i] - resampledDur
        Create Sound from formula: "UT_pad", 1, 0, padDur, samplingFrequency, "0"
        padID = selected("Sound")
        selectObject: shiftedLayerRaw
        plusObject: padID
        shiftedLayer = Concatenate
        Rename: "Shifted_" + string$(i)
        removeObject: shiftedLayerRaw, padID
    else
        shiftedLayer = shiftedLayerRaw
        selectObject: shiftedLayer
        Rename: "Shifted_" + string$(i)
    endif

    # --- Prepend entry-delay silence ---
    entryTime = entry[i]

    if entryTime > 0.001
        Create Sound from formula: "SilEntry_" + string$(i), 1,
        ... 0, entryTime, samplingFrequency, "0"
        silEntry = selected("Sound")
        selectObject: silEntry
        plusObject: shiftedLayer
        Concatenate
        withDelay = selected("Sound")
        Rename: "WithDelay_" + string$(i)
        removeObject: silEntry
        removeObject: shiftedLayer
    else
        withDelay = shiftedLayer
        selectObject: withDelay
        Rename: "WithDelay_" + string$(i)
    endif

    # --- Trim / pad end to totalDuration ---
    selectObject: withDelay
    currentTotal = Get total duration
    padNeeded    = totalDuration - currentTotal

    if padNeeded > 0.001
        Create Sound from formula: "SilEnd_" + string$(i), 1,
        ... 0, padNeeded, samplingFrequency, "0"
        silEnd = selected("Sound")
        selectObject: withDelay
        plusObject: silEnd
        Concatenate
        paddedLayer = selected("Sound")
        Rename: layerName$[i]
        removeObject: silEnd
        removeObject: withDelay
    elsif padNeeded < -0.001
        selectObject: withDelay
        Extract part: 0, totalDuration, "rectangular", 1, "yes"
        paddedLayer = selected("Sound")
        Rename: layerName$[i]
        removeObject: withDelay
    else
        paddedLayer = withDelay
        selectObject: paddedLayer
        Rename: layerName$[i]
    endif

    # --- Hanning fade-in at onset ---
    fadeStart     = entryTime
    fadeDurActual = fadeDur
    fadeEnd       = fadeStart + fadeDurActual

    if fadeEnd > totalDuration
        fadeEnd       = totalDuration
        fadeDurActual = fadeEnd - fadeStart
    endif

    if fadeDurActual > 0.001
        selectObject: paddedLayer
        Formula (part): fadeStart, fadeEnd, 1, 1,
        ... "self * (0.5 - 0.5 * cos(2 * pi * (x - fadeStart) / fadeDurActual))"
    endif

    # --- Accumulate into stereo buffers ---
    selectObject: accumL
    Formula: "self + object[paddedLayer] * panGainL[i]"

    selectObject: accumR
    Formula: "self + object[paddedLayer] * panGainR[i]"

    removeObject: paddedLayer

    appendInfoLine: "  ✓ ", layerName$[i], "  →  ", fixed$(targetFreq[i], 2), " Hz",
    ... "   pan ", fixed$(panPos[i], 2),
    ... "   L×", fixed$(panGainL[i], 3), "  R×", fixed$(panGainR[i], 3)

endfor

# ============================================================
# DRY SIGNAL — original centred at 0.707, scaled by dryMix
# ============================================================

selectObject: workSound
origActualDur = Get total duration
dryPadNeeded  = totalDuration - origActualDur

if dryPadNeeded > 0.001
    Create Sound from formula: "DrySilEnd", 1,
    ... 0, dryPadNeeded, samplingFrequency, "0"
    silDryEnd = selected("Sound")
    selectObject: workSound
    plusObject: silDryEnd
    Concatenate
    dryMono = selected("Sound")
    Rename: "DryMono"
    removeObject: silDryEnd
elsif dryPadNeeded < -0.001
    selectObject: workSound
    Extract part: 0, totalDuration, "rectangular", 1, "yes"
    dryMono = selected("Sound")
    Rename: "DryMono"
else
    selectObject: workSound
    Copy: "DryMono"
    dryMono = selected("Sound")
endif

if dryMix > 0.0
    dryCentreGain = 0.707
    selectObject: accumL
    Formula: "self + object[dryMono] * dryMix * dryCentreGain"
    selectObject: accumR
    Formula: "self + object[dryMono] * dryMix * dryCentreGain"
endif

removeObject: dryMono

if numChannels > 1
    removeObject: workSound
endif

# ============================================================
# COMBINE L + R → STEREO, NORMALISE, RENAME
# ============================================================

selectObject: accumL
plusObject: accumR
Combine to stereo
finalStereo = selected("Sound")

selectObject: finalStereo
Scale peak: 0.99

Rename: "Messagesquisse_Opening"

removeObject: accumL
removeObject: accumR

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    # Voice colors (blue→orange gradient across pan field)
    vColR[1] = 0.22
    vColG[1] = 0.48
    vColB[1] = 0.82
    vColR[2] = 0.35
    vColG[2] = 0.55
    vColB[2] = 0.65
    vColR[3] = 0.50
    vColG[3] = 0.62
    vColB[3] = 0.48
    vColR[4] = 0.68
    vColG[4] = 0.58
    vColB[4] = 0.28
    vColR[5] = 0.82
    vColG[5] = 0.45
    vColB[5] = 0.18
    vColR[6] = 0.90
    vColG[6] = 0.28
    vColB[6] = 0.12

    Erase all
    Black
    Line width: 1
    Font size: 10

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.0, 0.55
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half",
    ... "Messagesquisse Opening   [" + soundName$ + "]   MIDI " +
    ... string$(midiNote) + " (" + noteName$ + ")   preset: " + preset_name$

    # ----------------------------------------------------------
    # PANEL 1 — Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.60, 1.55
    Select inner viewport: 0.65, 7.65, 0.65, 1.50

    selectObject: originalSound
    inPeak = Get absolute extremum: 0, 0, "None"
    if inPeak < 0.001
        inPeak = 0.001
    endif
    ampMax = inPeak * 1.15

    Axes: 0, originalDuration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDuration, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, originalDuration, 0
    selectObject: originalSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original: " + soundName$

    # ----------------------------------------------------------
    # PANEL 2 — Output L channel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.60, 2.40
    Select inner viewport: 0.65, 7.65, 1.65, 2.35

    selectObject: finalStereo
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    outAmpMax = outPeak * 1.15

    Axes: 0, totalDuration, -outAmpMax, outAmpMax
    Paint rectangle: "{0.96, 0.97, 1.00}", 0, totalDuration, -outAmpMax, outAmpMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDuration, 0
    selectObject: finalStereo
    Extract one channel: 1
    leftCh = selected("Sound")
    Colour: "{0.20, 0.45, 0.82}"
    Draw: 0, 0, -outAmpMax, outAmpMax, "no", "Curve"
    removeObject: leftCh
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out L"

    # ----------------------------------------------------------
    # PANEL 3 — Output R channel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.44, 3.24
    Select inner viewport: 0.65, 7.65, 2.49, 3.19

    Axes: 0, totalDuration, -outAmpMax, outAmpMax
    Paint rectangle: "{1.00, 0.96, 0.95}", 0, totalDuration, -outAmpMax, outAmpMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDuration, 0
    selectObject: finalStereo
    Extract one channel: 2
    rightCh = selected("Sound")
    Colour: "{0.82, 0.22, 0.18}"
    Draw: 0, 0, -outAmpMax, outAmpMax, "no", "Curve"
    removeObject: rightCh
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out R"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL 4 — Layer accumulation timeline
    # Each voice: silent block (grey) + active block (colored)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.30, 4.70
    Select inner viewport: 0.65, 7.65, 3.38, 4.65

    rowH    = 1.0
    panelH  = 6.0 * rowH
    Axes: 0, totalDuration, 0, panelH

    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, 0, panelH

    # Entry time tick marks
    for i from 1 to 6
        if entry[i] > 0.0001
            Colour: "{0.80, 0.80, 0.80}"
            Dotted line
            Draw line: entry[i], 0, entry[i], panelH
            Solid line
        endif
    endfor

    for i from 1 to 6
        row     = 6 - i
        barBot  = row * rowH + 0.08
        barTop  = (row + 1) * rowH - 0.08

        # Silent pre-entry block (light grey)
        if entry[i] > 0.001
            Paint rectangle: "{0.88, 0.88, 0.88}", 0, entry[i], barBot, barTop
        endif

        # Active block (voice color)
        cR$ = fixed$(vColR[i], 2)
        cG$ = fixed$(vColG[i], 2)
        cB$ = fixed$(vColB[i], 2)
        vColor$ = "{" + cR$ + ", " + cG$ + ", " + cB$ + "}"
        Paint rectangle: vColor$, entry[i], totalDuration, barBot, barTop

        # Label inside bar
        Colour: "White"
        Font size: 7
        Text: entry[i] + activeDur[i] * 0.50, "centre",
        ... barBot + rowH * 0.42, "half",
        ... pitchName$[i] + "  " + fixed$(targetFreq[i], 1) + " Hz   pan " + fixed$(panPos[i], 2)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Layer"
    Text bottom: "yes", "Score time (s)"
    Text top: "no", "Layer Accumulation Timeline  (grey=silent  colored=active drone)"

    # ----------------------------------------------------------
    # PANEL 5 — Stereo pan field map
    # ----------------------------------------------------------
    Select outer viewport: 0, 5.5, 4.78, 5.60
    Select inner viewport: 0.65, 5.20, 4.85, 5.55

    Axes: -1.15, 1.15, -0.3, 1.0
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.15, 1.15, -0.3, 1.0

    # Stereo field baseline
    Colour: "{0.70, 0.70, 0.70}"
    Line width: 2
    Draw line: -1.0, 0.5, 1.0, 0.5
    Line width: 1

    # L / R labels
    Colour: "{0.20, 0.45, 0.82}"
    Font size: 7
    Text: -1.0, "centre", 0.82, "half", "L"
    Colour: "{0.82, 0.22, 0.18}"
    Text:  1.0, "centre", 0.82, "half", "R"
    Colour: "{0.60, 0.60, 0.60}"
    Text:  0.0, "centre", 0.82, "half", "C"

    # Centre reference tick
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, 0.2, 0, 0.8
    Solid line

    # Voice dots on the field line
    for i from 1 to 6
        dotR = vColR[i]
        dotG = vColG[i]
        dotB = vColB[i]
        Paint circle (mm): "{" + fixed$(dotR,2) + ", " + fixed$(dotG,2) + ", " + fixed$(dotB,2) + "}", panPos[i], 0.5, 2.8
        Colour: "Black"
        Font size: 6
        Text: panPos[i], "centre", 0.18, "half", pitchName$[i]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Stereo Pan Map  (L←  " + fixed$(pSpread*100,0) + "% spread  →R)"

    # ----------------------------------------------------------
    # PANEL 6 — MIDI / pitch ladder
    # Shows the six SACHER pitches as horizontal bars
    # ----------------------------------------------------------
    Select outer viewport: 5.5, 8, 4.78, 5.60
    Select inner viewport: 5.68, 7.65, 4.85, 5.55

    # Frequency range for y axis
    fMin = targetFreq[3] * 0.85
    fMax = targetFreq[2] * 1.15
    Axes: 0, 1, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, fMin, fMax

    for i from 1 to 6
        bR = vColR[i]
        bG = vColG[i]
        bB = vColB[i]
        Paint rectangle: "{" + fixed$(bR,2) + ", " + fixed$(bG,2) + ", " + fixed$(bB,2) + "}",
        ... 0.1, 0.75, targetFreq[i] - (fMax-fMin)*0.025, targetFreq[i] + (fMax-fMin)*0.025
        Colour: "Black"
        Font size: 6
        Text: 0.80, "left", targetFreq[i], "half", pitchName$[i] + "  " + fixed$(targetFreq[i],1)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "SACHER Pitches"

    # ----------------------------------------------------------
    # STATS FOOTER
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.65, 6.20
    Select inner viewport: 0.30, 7.80, 5.70, 6.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.01, "left", 0.82, "half",
    ... "##Messagesquisse Opening v4.4  | SACHER Hexachord  |  Morse Temporal Structure##"
    Colour: "{0.35, 0.35, 0.60}"
    Text: 0.80, "left", 0.82, "half", "Preset: " + preset_name$
    Font size: 6
    Colour: "{0.30, 0.30, 0.35}"
    Text: 0.01, "left", 0.55, "half",
    ... "Source: " + soundName$ + "  (" + fixed$(originalDuration, 3) + " s)" +
    ... "   Base: MIDI " + string$(midiNote) + " (" + noteName$ + " = " + fixed$(baseFreq, 2) + " Hz)" +
    ... "   dot=" + fixed$(dot, 4) + " s   Score=" + fixed$(totalDuration, 3) + " s"
    Text: 0.01, "left", 0.30, "half",
    ... "Wet=" + fixed$(wetMix*100, 0) + "%   Dry=" + fixed$(dryMix*100, 0) + "%" +
    ... "   Pan spread=" + fixed$(pSpread*100, 0) + "%" +
    ... "   Fade=" + fixed$(fadeDur*1000, 1) + " ms" +
    ... "   Loop=" + string$(loopShort) +
    ... "   SR=" + string$(samplingFrequency) + " Hz"
    Text: 0.01, "left", 0.08, "half",
    ... "Layers:  " +
    ... "Eb=" + fixed$(targetFreq[1],1) + "Hz  " +
    ... "A=" + fixed$(targetFreq[2],1) + "Hz  " +
    ... "C=" + fixed$(targetFreq[3],1) + "Hz  " +
    ... "B=" + fixed$(targetFreq[4],1) + "Hz  " +
    ... "E=" + fixed$(targetFreq[5],1) + "Hz  " +
    ... "D=" + fixed$(targetFreq[6],1) + "Hz"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# SUMMARY
# ============================================================

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: "Output   : Messagesquisse_Opening  (stereo)"
appendInfoLine: "Duration : ", fixed$(totalDuration, 3), " s"
appendInfoLine: "Base     : MIDI ", midiNote, "  (", noteName$, " = ", fixed$(baseFreq, 2), " Hz)"
appendInfoLine: "Wet/Dry  : ", fixed$(wetMix*100,1), "% / ", fixed$(dryMix*100,1), "%"
appendInfoLine: "Pan      : ", fixed$(pSpread*100,0), "% spread"
appendInfoLine: "Preset   : ", preset_name$

# ============================================================
# PLAY
# ============================================================

selectObject: finalStereo

if play_result = 1
    Play
endif