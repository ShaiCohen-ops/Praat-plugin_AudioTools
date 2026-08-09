# ============================================================
# Praat AudioTools - Messagesquisse_Opening.praat (v4.7a)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.7a (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Boulez-inspired additive drone machine after Messagesquisse.
#   Transforms a single cello tone into a six-layer hexachordal
#   field using the SACHER pitch set and Morse-derived timing.
#
# Changelog v4.7a (2026):
#   - FIX: removed a premature report reference to safetyApplied.
#     The variable is only defined after final stereo peak analysis.
#
# Changelog v4.7 (2026):
#   - FIX (Morse entry alignment): entry silence is now guaranteed to precede
#     each shifted layer. Praat Concatenate follows Objects-list creation order,
#     not selection order; the old entry-silence block could therefore place
#     audio before silence. A fresh post-silence layer copy fixes the ordering.
#   - FIX (non-zero input time domains): stores source xmin/xmax, converts
#     score-relative source positions to absolute source times for extraction,
#     and makes all internal working segments intentionally zero-based.
#   - FIX (dry extraction): dry-path trimming/padding also respects source xmin.
#   - SAFETY: validates source/target pitch frequencies against the current
#     sampling rate and rejects invalid resample rates.
#   - SPEED: skips the six-layer wet render entirely when Wet_mix = 0, and
#     skips dry preparation when Dry_mix = 0.
#   - OUTPUT: final peak handling is attenuation-only; quiet outputs are not
#     boosted to 0.99.
#   - VIS: the input waveform panel uses the source's real xmin/xmax domain.
#
# Changelog v4.6 (2026) — response to internal review:
#   - FIX (presets clobbering Source_pitch_MIDI): the six preset
#     overrides were also resetting source_pitch_MIDI = 36, so
#     choosing any preset silently discarded whatever fundamental
#     the user had entered for their own input file. Presets now
#     only touch what they conceptually own (register, wet/dry,
#     pan, fades) and leave Source_pitch_MIDI alone.
#   - FIX (Dry/Wet): wet layers were accumulated at full gain and
#     were never multiplied by wetMix, so Wet_mix behaved as an
#     on/off toggle rather than a crossfade. Wet layers are now
#     scaled by wetMix, so wetMix=0 is dry-only, wetMix=1 is
#     wet-only, and intermediate values genuinely crossfade.
#   - FIX (Quartertone Haze): Base_MIDI_note is an integer field
#     and could never express "+50 cents", so the preset silently
#     fell back to a plain C2. Added a separate real-valued
#     Quartertone_offset_semitones field; the Quartertone Haze
#     preset now sets it to 0.5 (50 cents), which detunes the
#     whole hexachord register independent of the integer MIDI note.
#   - FIX (register presets): pitch-shift ratio pf = targetFreq/baseFreq
#     previously used the SAME baseFreq on top and bottom, so it
#     depended only on the SACHER semitone offsets and Base_MIDI_note
#     cancelled out — "Low Drone Field" and "High Shimmer" produced
#     identical audio, differing only in the printed Hz labels.
#     Base_MIDI_note is now the TARGET/root register (what the six
#     layers transpose to), while a new fixed Source_pitch_MIDI
#     (assumed fundamental of the input, default C2/36) anchors the
#     ratio, so changing the register preset now actually changes
#     the transposition applied to the audio.
#   - FIX: added a short equal-power fade-out at the end of the
#     final stereo file so standalone renders don't end in an
#     abrupt cut.
#   - FIX: added an explicit "Axes: 0, 1, 0, 1" call for the title
#     panel so its text position no longer depends on whatever
#     axes state the Picture window was left in.
#   - NOTE (Morse units): re-checked by hand — S=5, A=5, C=11,
#     H=7, E=1, R=7 dot-units = 36 total, matching totalUnits=36
#     and auto_unit = originalDuration/36 exactly. No change needed;
#     this one was a false alarm in the review (C is "-.-.", i.e.
#     4 symbols + 3 gaps = 3+1+1+1+3+1+1 = 11, not 9).
#
# Changelog v4.5 (2026):
#   - FIX: The Hanning fade-in was using "cos(2 * pi * x / dur)" which
#     ramps 0 -> 1 -> 0 over the fade window (a brief pulse at each
#     layer entry, not a fade-in). Changed to "cos(pi * x / dur)"
#     so the ramp is monotonic 0 -> 1 as intended.
#   - SPEED: Per-layer resample precision is now tied to a
#     Speed_mode parameter (Full Quality / Balanced / Fast =
#     precision 50 / 20 / 10). Six layers means six resamples
#     per run, so Balanced or Fast is a real time saving on
#     longer inputs.
#
#   PITCH STRUCTURE — SACHER hexachord (Boulez, 1975):
#     S  A  C  H  E  R
#     Eb A  C  B  E  D
#     Semitone offsets from C: [3, 9, 0, 11, 4, 2]
#     Each layer pitch-shifted via Sample Rate Reinterpretation.
#     Base_MIDI_note = TARGET/root register the hexachord transposes
#     to. Source_pitch_MIDI = assumed fundamental of the input
#     recording (default C2/36) used only to compute the transposition
#     ratio. Quartertone_offset_semitones detunes the whole target
#     register (0.5 = 50 cents).
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
#     Dry = original (centred, 0.707 gain on both channels), scaled
#     by (1 - wet_mix).
#     Wet = six processed pitch-shifted layers, scaled by wet_mix.
#     wet_mix 0→1 is a true crossfade between pure original and
#     the full processed field.
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
sourceXmin        = Get start time
sourceXmax        = Get end time
originalDuration  = sourceXmax - sourceXmin
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

form Messagesquisse Opening v4.7a
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Boulez Reference   (C2, full spread, 80% wet)
        option Low Drone Field    (C1, full spread, 90% wet)
        option High Shimmer       (C4, full spread, 70% wet)
        option Centred Mass       (C2, no spread, 100% wet)
        option Dry Ghost          (C2, full spread, 20% wet)
        option Quartertone Haze   (C2+50ct, partial spread, 75% wet)
    comment === Target register (MIDI note the hexachord transposes to, C2=36) ===
    integer  Base_MIDI_note 36
    comment === Quartertone detune of the target register [semitones, e.g. 0.5 = 50 cents] ===
    real     Quartertone_offset_semitones 0.0
    comment === Assumed fundamental of the INPUT recording [MIDI note, default C2=36] (presets never override this — it describes your file, not the preset) ===
    integer  Source_pitch_MIDI 36
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
    comment === Render speed (per-layer resample precision) ===
    optionmenu Speed_mode: 2
        option Full Quality (precision 50)
        option Balanced (precision 20)
        option Fast (precision 10)
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
    quartertone_offset_semitones = 0.0
    unit_duration_s  = 0.0
    fade_duration_s  = 0.05
    pan_spread       = 1.0
    wet_mix          = 0.80
    loop_if_short    = 1

elsif preset = 3
    preset_name$     = "Low Drone Field"
    base_MIDI_note   = 24
    quartertone_offset_semitones = 0.0
    unit_duration_s  = 0.0
    fade_duration_s  = 0.08
    pan_spread       = 1.0
    wet_mix          = 0.90
    loop_if_short    = 1

elsif preset = 4
    preset_name$     = "High Shimmer"
    base_MIDI_note   = 60
    quartertone_offset_semitones = 0.0
    unit_duration_s  = 0.0
    fade_duration_s  = 0.03
    pan_spread       = 1.0
    wet_mix          = 0.70
    loop_if_short    = 1

elsif preset = 5
    preset_name$     = "Centred Mass"
    base_MIDI_note   = 36
    quartertone_offset_semitones = 0.0
    unit_duration_s  = 0.0
    fade_duration_s  = 0.05
    pan_spread       = 0.0
    wet_mix          = 1.0
    loop_if_short    = 1

elsif preset = 6
    preset_name$     = "Dry Ghost"
    base_MIDI_note   = 36
    quartertone_offset_semitones = 0.0
    unit_duration_s  = 0.0
    fade_duration_s  = 0.05
    pan_spread       = 1.0
    wet_mix          = 0.20
    loop_if_short    = 0

elsif preset = 7
    preset_name$     = "Quartertone Haze"
    base_MIDI_note   = 36
    quartertone_offset_semitones = 0.5
    unit_duration_s  = 0.0
    fade_duration_s  = 0.06
    pan_spread       = 0.65
    wet_mix          = 0.75
    loop_if_short    = 1

endif

# ============================================================
# ALIASES & DERIVED PARAMETERS
# ============================================================

midiNote     = base_MIDI_note
qtOffset     = quartertone_offset_semitones
sourceMidi   = source_pitch_MIDI
fadeDur      = fade_duration_s
pSpread      = pan_spread
wetMix       = wet_mix
dryMix       = 1.0 - wetMix
loopShort    = loop_if_short

# v4.5: resample precision tied to speed_mode.
# Per-layer pitch shift (Override SR -> Resample) runs once per
# layer (six total). Lower precision is acceptable for sustained
# drone material and gives a real time saving on longer inputs.
if speed_mode = 1
    resamplePrecision = 50
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    resamplePrecision = 20
    speedStr$ = "Balanced"
else
    resamplePrecision = 10
    speedStr$ = "Fast"
endif

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
# baseFreq is the TARGET/root register the SACHER hexachord transposes
# to (Base_MIDI_note, plus any quartertone detune). sourcePitchFreq is
# the assumed fundamental of the INPUT recording (Source_pitch_MIDI)
# and is what actually anchors the pitch-shift ratio below — this is
# what makes changing the register preset (Low Drone / High Shimmer)
# audibly change the processed output, rather than only the printed
# Hz labels.
baseFreq       = 440.0 * (2 ^ ((midiNote + qtOffset - 69) / 12.0))
sourcePitchFreq = 440.0 * (2 ^ ((sourceMidi - 69) / 12.0))

if sourcePitchFreq <= 0 or sourcePitchFreq >= 0.45 * samplingFrequency
    if numChannels > 1
        removeObject: workSound
    endif
    exitScript: "Source_pitch_MIDI maps to an unsafe frequency (" + fixed$(sourcePitchFreq, 2) + " Hz)." + newline$
        ... + "Choose a value below 45% of the sampling frequency."
endif

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
if qtOffset <> 0.0
    qtCents$  = fixed$(qtOffset * 100, 0)
    if qtOffset > 0
        noteName$ = noteName$ + "+" + qtCents$ + "ct"
    else
        noteName$ = noteName$ + qtCents$ + "ct"
    endif
endif

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
    if targetFreq[i] <= 0 or targetFreq[i] >= 0.45 * samplingFrequency
        if numChannels > 1
            removeObject: workSound
        endif
        exitScript: "Target layer " + string$(i) + " is outside the safe output pitch range (" +
            ... fixed$(targetFreq[i], 2) + " Hz)." + newline$
            ... + "Lower Base_MIDI_note / Quartertone_offset_semitones."
    endif
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
appendInfoLine: "  Messagesquisse Opening v4.7a"
appendInfoLine: "==================================================="
appendInfoLine: "Source   : ", soundName$, "  (", fixed$(originalDuration, 3), " s)"
appendInfoLine: "Target reg: MIDI ", midiNote, "  (", noteName$, " = ", fixed$(baseFreq, 2), " Hz)"
appendInfoLine: "Src pitch : MIDI ", sourceMidi, "  (assumed = ", fixed$(sourcePitchFreq, 2), " Hz)"
appendInfoLine: "dot=", fixed$(dot, 4), " s   dash=", fixed$(dash, 4), " s"
appendInfoLine: "Score dur: ", fixed$(totalDuration, 4), " s"
appendInfoLine: "Wet mix  : ", fixed$(wetMix * 100, 1), "%   Pan spread: ", fixed$(pSpread * 100, 1), "%"
appendInfoLine: "Speed    : ", speedStr$, "  (resample precision=", resamplePrecision, ")"
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

if wetMix > 0.0
    for i from 1 to 6

        # 1. Calculate pitch factor (ratio of target to assumed source pitch).
        pf = targetFreq[i] / sourcePitchFreq

        # Override sampling frequency must remain positive and computationally sane.
        oSr = round(samplingFrequency * pf)
        if oSr < 1000 or oSr > 2000000
            removeObject: accumL, accumR
            if numChannels > 1
                removeObject: workSound
            endif
            exitScript: "Layer " + string$(i) + " requires an unsafe temporary sampling frequency (" +
                ... string$(oSr) + " Hz)." + newline$
                ... + "Choose a less extreme target/source register relationship."
        endif

        # 2. Sample-rate reinterpretation changes duration, so request a source
        # segment scaled by pf to obtain activeDur[i] after pitch shifting.
        reqDur = activeDur[i] * pf

        # Score-relative source position (seconds from source onset).
        srcStartRel = entry[i]
        srcEndRel   = srcStartRel + reqDur
        needsLoop   = 0

        if srcStartRel >= originalDuration
            srcStartRel = originalDuration - 0.01
            if srcStartRel < 0
                srcStartRel = 0
            endif
        endif

        if srcEndRel > originalDuration
            needsLoop = 1
            srcEndRel = originalDuration
        endif

        # Convert relative score time to the source Sound's absolute domain.
        srcStartAbs = sourceXmin + srcStartRel
        srcEndAbs   = sourceXmin + srcEndRel

        # --- Extract source segment ---
        # Preserve times = no: every internal layer segment is intentionally
        # zero-based from this point onward.
        selectObject: workSound
        Extract part: srcStartAbs, srcEndAbs, "Hanning", 1, "no"
        srcSegment = selected("Sound")
        Rename: "SrcSeg_" + string$(i)

        segDur = Get total duration
        remainingNeeded = reqDur - segDur

        # --- Loop or pad if source overruns ---
        if needsLoop = 1 and remainingNeeded > 0.001

            if loopShort = 1
                if segDur <= 0.000001
                    removeObject: srcSegment, accumL, accumR
                    if numChannels > 1
                        removeObject: workSound
                    endif
                    exitScript: "A source segment became too short to loop."
                endif

                nCopies = ceiling(reqDur / segDur) + 1

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
                Extract part: 0, reqDur, "rectangular", 1, "no"
                sourceReady = selected("Sound")
                Rename: "SourceReady_" + string$(i)
                removeObject: loopBase, srcSegment
            else
                Create Sound from formula: "SilPad_" + string$(i), 1,
                    ... 0, remainingNeeded, samplingFrequency, "0"
                silPad = selected("Sound")

                # srcSegment was created before silPad, so Objects-list order is
                # audio -> silence, which is the desired tail padding.
                selectObject: srcSegment
                plusObject: silPad
                Concatenate
                sourceReady = selected("Sound")
                Rename: "SourceReady_" + string$(i)
                removeObject: silPad, srcSegment
            endif

        else
            selectObject: srcSegment
            currentSegDur = Get total duration
            if currentSegDur > reqDur + 0.001
                Extract part: 0, reqDur, "rectangular", 1, "no"
                sourceReady = selected("Sound")
                Rename: "SourceReady_" + string$(i)
                removeObject: srcSegment
            else
                sourceReady = srcSegment
                selectObject: sourceReady
                Rename: "SourceReady_" + string$(i)
            endif
        endif

        # --- Pitch shift via Sample Rate Reinterpretation ---
        selectObject: sourceReady
        Override sampling frequency: oSr
        shiftedLayerRaw = Resample: samplingFrequency, resamplePrecision
        removeObject: sourceReady

        # Trim or pad to exact activeDur[i] to ensure alignment.
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

            # shiftedLayerRaw predates padID -> correct audio-then-silence order.
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

            # CRITICAL v4.7 ordering fix:
            # Concatenate uses Objects-list creation order, not selection order.
            # shiftedLayer existed before silEntry, so selecting silEntry first
            # was not enough. Make a fresh shifted copy AFTER the silence.
            selectObject: shiftedLayer
            shiftedAfterSilence = Copy: "ShiftAfterSil_" + string$(i)

            selectObject: silEntry
            plusObject: shiftedAfterSilence
            Concatenate
            withDelay = selected("Sound")
            Rename: "WithDelay_" + string$(i)

            removeObject: silEntry, shiftedAfterSilence, shiftedLayer
        else
            withDelay = shiftedLayer
            selectObject: withDelay
            Rename: "WithDelay_" + string$(i)
        endif

        # --- Trim / pad end to totalDuration ---
        selectObject: withDelay
        currentTotal = Get total duration
        padNeeded = totalDuration - currentTotal

        if padNeeded > 0.001
            Create Sound from formula: "SilEnd_" + string$(i), 1,
                ... 0, padNeeded, samplingFrequency, "0"
            silEnd = selected("Sound")

            # withDelay predates silEnd -> correct audio-then-silence order.
            selectObject: withDelay
            plusObject: silEnd
            Concatenate
            paddedLayer = selected("Sound")
            Rename: layerName$[i]
            removeObject: silEnd, withDelay

        elsif padNeeded < -0.001
            selectObject: withDelay
            Extract part: 0, totalDuration, "rectangular", 1, "no"
            paddedLayer = selected("Sound")
            Rename: layerName$[i]
            removeObject: withDelay
        else
            paddedLayer = withDelay
            selectObject: paddedLayer
            Rename: layerName$[i]
        endif

        # --- Hanning fade-in at onset ---
        fadeStart = entryTime
        fadeDurActual = fadeDur
        fadeEnd = fadeStart + fadeDurActual

        if fadeEnd > totalDuration
            fadeEnd = totalDuration
            fadeDurActual = fadeEnd - fadeStart
        endif

        if fadeDurActual > 0.001
            selectObject: paddedLayer
            Formula (part): fadeStart, fadeEnd, 1, 1,
                ... "self * (0.5 - 0.5 * cos(pi * (x - fadeStart) / fadeDurActual))"
        endif

        # --- Accumulate into stereo buffers ---
        selectObject: accumL
        Formula: "self + object[paddedLayer] * panGainL[i] * wetMix"

        selectObject: accumR
        Formula: "self + object[paddedLayer] * panGainR[i] * wetMix"

        removeObject: paddedLayer

        appendInfoLine: "  ✓ ", layerName$[i], "  →  ", fixed$(targetFreq[i], 2), " Hz",
            ... "   pan ", fixed$(panPos[i], 2),
            ... "   L×", fixed$(panGainL[i], 3), "  R×", fixed$(panGainR[i], 3)
    endfor
else
    appendInfoLine: "Wet mix = 0: skipped six-layer render."
endif

# ============================================================
# DRY SIGNAL — source centred at 0.707, scaled by dryMix
# ============================================================

if dryMix > 0.0
    # Build a zero-based dry working segment from the source's real time domain.
    if originalDuration > totalDuration + 0.001
        selectObject: workSound
        Extract part: sourceXmin, sourceXmin + totalDuration, "rectangular", 1, "no"
        dryMono = selected("Sound")
        Rename: "DryMono"

    elsif originalDuration < totalDuration - 0.001
        selectObject: workSound
        Extract part: sourceXmin, sourceXmax, "rectangular", 1, "no"
        dryBase = selected("Sound")
        Rename: "DryBase"

        dryPadNeeded = totalDuration - originalDuration
        Create Sound from formula: "DrySilEnd", 1,
            ... 0, dryPadNeeded, samplingFrequency, "0"
        silDryEnd = selected("Sound")

        # dryBase predates silDryEnd -> correct audio-then-silence order.
        selectObject: dryBase
        plusObject: silDryEnd
        Concatenate
        dryMono = selected("Sound")
        Rename: "DryMono"
        removeObject: dryBase, silDryEnd
    else
        selectObject: workSound
        Extract part: sourceXmin, sourceXmax, "rectangular", 1, "no"
        dryMono = selected("Sound")
        Rename: "DryMono"
    endif

    dryCentreGain = 0.707

    selectObject: accumL
    Formula: "self + object[dryMono] * dryMix * dryCentreGain"

    selectObject: accumR
    Formula: "self + object[dryMono] * dryMix * dryCentreGain"

    removeObject: dryMono
else
    appendInfoLine: "Dry mix = 0: skipped dry-path preparation."
endif

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
finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.99
    Scale peak: 0.99
    safetyApplied = 1
else
    safetyApplied = 0
endif

Rename: "Messagesquisse_Opening"

removeObject: accumL
removeObject: accumR

# ------------------------------------------------------------
# FINAL FADE-OUT
# All six layers are active right up to totalDuration and were
# previously cut off in one block, risking a click/abrupt ending.
# Add a short cosine (equal-power-ish) fade-out at the tail.
# ------------------------------------------------------------
finalFadeDur = fadeDur * 3
if finalFadeDur > totalDuration * 0.25
    finalFadeDur = totalDuration * 0.25
endif

if finalFadeDur > 0.001
    fadeOutStart = totalDuration - finalFadeDur
    selectObject: finalStereo
    Formula (part): fadeOutStart, totalDuration, 1, 2,
    ... "self * (0.5 + 0.5 * cos(pi * (x - fadeOutStart) / finalFadeDur))"
endif

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
    Axes: 0, 1, 0, 1
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

    Axes: sourceXmin, sourceXmax, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", sourceXmin, sourceXmax, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sourceXmin, 0, sourceXmax, 0
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
    ... "##Messagesquisse Opening v4.7a  | SACHER Hexachord  |  Morse Temporal Structure##"
    Colour: "{0.35, 0.35, 0.60}"
    Text: 0.80, "left", 0.82, "half", "Preset: " + preset_name$
    Font size: 6
    Colour: "{0.30, 0.30, 0.35}"
    Text: 0.01, "left", 0.55, "half",
    ... "Source: " + soundName$ + "  (" + fixed$(originalDuration, 3) + " s)" +
    ... "   Target reg: MIDI " + string$(midiNote) + " (" + noteName$ + " = " + fixed$(baseFreq, 2) + " Hz)" +
    ... "   Src pitch: MIDI " + string$(sourceMidi) + " (" + fixed$(sourcePitchFreq, 2) + " Hz)" +
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
appendInfoLine: "Target reg: MIDI ", midiNote, "  (", noteName$, " = ", fixed$(baseFreq, 2), " Hz)"
appendInfoLine: "Src pitch : MIDI ", sourceMidi, "  (assumed = ", fixed$(sourcePitchFreq, 2), " Hz)"
appendInfoLine: "Wet/Dry  : ", fixed$(wetMix*100,1), "% / ", fixed$(dryMix*100,1), "%"
appendInfoLine: "Pan      : ", fixed$(pSpread*100,0), "% spread"
appendInfoLine: "Preset   : ", preset_name$
appendInfoLine: "Peak safety: ", safetyApplied

# ============================================================
# PLAY
# ============================================================

selectObject: finalStereo

if play_result = 1
    Play
endif