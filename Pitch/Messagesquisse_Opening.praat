# ============================================================
# Praat AudioTools - Messagesquisse_Opening.praat (v4.8)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.10 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Boulez-inspired additive drone machine after Messagesquisse.
#   Transforms a single cello tone into a six-layer hexachordal
#   field using the SACHER pitch set and Morse-derived timing.
#
# Changelog v4.8.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v4.8: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
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

form Messagesquisse Opening v4.8.1
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
appendInfoLine: "  Messagesquisse Opening v4.8.1"
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
#
# Canvas: 8.0 x 8.62 in.  All panels share the 0.65 / 7.65 horizontal grid.
#
#   Input waveform                          source time
#   Measured output envelope (L up / R down)
#   Morse score strip                       } all on SCORE time, 0..totalDuration
#   Layer accumulation timeline             |  (ticks on every panel, numbers
#   Stereo accumulation (L up / R down)     /   only on the last one)
#   Pitch x Pan field
#   Summary
#
# v4.9 changes: three overprinted axis labels separated; every "%" escaped
# (it is italic markup and was being swallowed); axis numbers added throughout;
# one summary box instead of two; pitch ladder moved to a semitone axis and
# merged with the pan map; new stereo accumulation panel.
# ============================================================

if draw_visualization = 1

    canvasH = 8.10

    # Voice colors (blue -> orange gradient across the pan field)
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

    for i from 1 to 6
        vCol$[i] = "{" + fixed$(vColR[i],2) + ", " + fixed$(vColG[i],2) + ", " + fixed$(vColB[i],2) + "}"
    endfor

    Erase all
    Black
    Line width: 1
    Solid line
    Select outer viewport: 0, 8, 0, canvasH

    @niceTick: totalDuration
    tickScore = niceTick.t
    @niceTick: sourceXmax - sourceXmin
    tickSrc = niceTick.t

    # ----------------------------------------------------------
    # TITLE
    # A title strip must use Select INNER viewport: Axes maps to the inner
    # viewport, so an outer-viewport strip is silently inset by the standard
    # margins and its text lands lower than the strip implies — which is how
    # the panel-1 caption came to print through the title in v4.8.
    # ----------------------------------------------------------
    Font size: 12
    Select inner viewport: 0.65, 7.65, 0.04, 0.40
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.78, "half", "##Messagesquisse Opening##"
    Font size: 7
    Select inner viewport: 0.65, 7.65, 0.04, 0.40
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
    ... soundName$ + "  |  target MIDI " + string$(midiNote) + " (" + noteName$ + ")"
    ... + "  |  preset: " + preset_name$
    ... + "  |  dot=" + fixed$(dot, 3) + " s"
    ... + "  |  wet " + fixed$(wetMix*100, 0) + "\%  / dry " + fixed$(dryMix*100, 0) + "\%  "

    # ----------------------------------------------------------
    # PANEL 1 — Input waveform
    # ----------------------------------------------------------
    selectObject: originalSound
    inPeak = Get absolute extremum: 0, 0, "None"
    if inPeak < 0.001
        inPeak = 0.001
    endif
    ampMax = inPeak * 1.15

    Font size: 7
    Select outer viewport: 0, 8, 0.44, 1.22
    Select inner viewport: 0.65, 7.65, 0.54, 1.10
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
    Select inner viewport: 0.65, 7.65, 0.54, 1.10
    Axes: sourceXmin, sourceXmax, -ampMax, ampMax
    Marks bottom every: 1, tickSrc, "yes", "yes", "no"
    Text bottom: "yes", "Source time (s)"
    Text top: "no", "Original source: " + soundName$
    @railLabelAt: 0.65, 7.65, 0.54, 1.10, 7, 0.32, "Input"

    selectObject: finalStereo
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif

    # ----------------------------------------------------------
    # PANEL 2 — Measured output envelope (L up / R down)
    #
    # v4.8 gave L and R a full waveform panel each.  Two panels of dense
    # drone hair is a lot of page for a comparison the reader then has to
    # make by eye across a gap; one mirrored envelope puts L against R
    # directly, in the same grammar as the predicted stack below it.
    #
    # This panel is MEASURED (windowed RMS of the rendered file); the stack
    # below is PREDICTED from the entry times, fade shape and pan law.  They
    # are not redundant: score-advancing segmentation means layer i reads
    # original[entry_i ...], so a quiet passage in the source makes that voice
    # quiet, and no parameter-derived panel can show it.  The correlation
    # printed in the caption is how closely the render actually followed the
    # plan on this run.
    # ----------------------------------------------------------
    enX1 = 0.65
    enX2 = 7.65
    enY1 = 1.72
    enY2 = 2.34

    Select outer viewport: 0, 8, 1.54, 2.44

    selectObject: finalStereo
    Extract one channel: 1
    envL = selected("Sound")
    selectObject: finalStereo
    Extract one channel: 2
    envR = selected("Sound")

    nEnvCols = 240
    if totalDuration / nEnvCols * samplingFrequency < 16
        nEnvCols = floor(totalDuration * samplingFrequency / 16)
    endif
    if nEnvCols < 20
        nEnvCols = 20
    endif
    envW = totalDuration / nEnvCols
    envDry = dryMix * 0.707

    # Pass 1: raw windowed RMS, plus the predicted gain at the same instants.
    for c from 1 to nEnvCols
        cT0 = (c - 1) * envW
        cT1 = c * envW
        cTm = (cT0 + cT1) / 2
        selectObject: envL
        mL = Get root-mean-square: cT0, cT1
        selectObject: envR
        mR = Get root-mean-square: cT0, cT1
        if mL = undefined
            mL = 0
        endif
        if mR = undefined
            mR = 0
        endif
        envRawL[c] = mL
        envRawR[c] = mR

        pL = envDry
        pR = envDry
        for i from 1 to 6
            if cTm < entry[i]
                env = 0
            elsif fadeDur > 0.001 and cTm < entry[i] + fadeDur
                env = 0.5 - 0.5 * cos(pi * (cTm - entry[i]) / fadeDur)
            else
                env = 1
            endif
            pL = pL + wetMix * panGainL[i] * env
            pR = pR + wetMix * panGainR[i] * env
        endfor
        envPreL[c] = pL
        envPreR[c] = pR
    endfor
    removeObject: envL, envR

    # Pass 2: 5-point moving average.  Six sustained drones a semitone or two
    # apart beat against each other, so the raw per-window RMS is hash at this
    # panel height; smoothing keeps the shape and drops the hair.  The
    # correlation below is computed on the SMOOTHED values, i.e. on what is
    # actually drawn.
    envSm = 2
    envMax = 0.0001
    sumML = 0
    sumMR = 0
    sumPL = 0
    sumPR = 0
    sumMLPL = 0
    sumMRPR = 0
    sumML2 = 0
    sumMR2 = 0
    sumPL2 = 0
    sumPR2 = 0
    for c from 1 to nEnvCols
        accL = 0
        accR = 0
        nAcc = 0
        for k from c - envSm to c + envSm
            if k >= 1 and k <= nEnvCols
                accL = accL + envRawL[k]
                accR = accR + envRawR[k]
                nAcc = nAcc + 1
            endif
        endfor
        mL = accL / nAcc
        mR = accR / nAcc
        envValL[c] = mL
        envValR[c] = mR
        if mL > envMax
            envMax = mL
        endif
        if mR > envMax
            envMax = mR
        endif
        pL = envPreL[c]
        pR = envPreR[c]
        sumML += mL
        sumMR += mR
        sumPL += pL
        sumPR += pR
        sumMLPL += mL * pL
        sumMRPR += mR * pR
        sumML2 += mL * mL
        sumMR2 += mR * mR
        sumPL2 += pL * pL
        sumPR2 += pR * pR
    endfor

    @pearson: nEnvCols, sumML, sumPL, sumMLPL, sumML2, sumPL2
    corrL = pearson.r
    @pearson: nEnvCols, sumMR, sumPR, sumMRPR, sumMR2, sumPR2
    corrR = pearson.r

    envMax = envMax * 1.15
    @niceTickN: 2 * envMax, 5
    tickEnv = niceTickN.t

    Font size: 6
    Select inner viewport: enX1, enX2, enY1, enY2
    Axes: 0, totalDuration, -envMax, envMax
    Paint rectangle: "{0.975, 0.977, 0.985}", 0, totalDuration, -envMax, envMax

    for c from 1 to nEnvCols
        cT0 = (c - 1) * envW
        cT1 = c * envW
        Paint rectangle: "{0.20, 0.45, 0.82}", cT0, cT1, 0, envValL[c]
        Paint rectangle: "{0.82, 0.22, 0.18}", cT0, cT1, -envValR[c], 0
    endfor

    Font size: 6
    Select inner viewport: enX1, enX2, enY1, enY2
    Axes: 0, totalDuration, -envMax, envMax
    Colour: "{0.30, 0.30, 0.30}"
    Line width: 1
    Draw line: 0, 0, totalDuration, 0
    Colour: "{0.20, 0.45, 0.82}"
    Text: totalDuration * 0.012, "left", envMax * 0.72, "half", "##L##"
    Colour: "{0.82, 0.22, 0.18}"
    Text: totalDuration * 0.012, "left", -envMax * 0.72, "half", "##R##"
    Colour: "Black"
    Select inner viewport: enX1, enX2, enY1, enY2
    Axes: 0, totalDuration, -envMax, envMax
    Draw inner box

    Font size: 6
    Select inner viewport: enX1, enX2, enY1, enY2
    Axes: 0, totalDuration, -envMax, envMax
    Marks bottom every: 1, tickScore, "no", "yes", "no"
    Marks left every: 1, tickEnv, "yes", "yes", "no"

    Font size: 7
    Select inner viewport: enX1, enX2, enY1, enY2
    Axes: 0, totalDuration, -envMax, envMax
    corrTxt$ = "r = " + fixed$(corrL, 2) + " L / " + fixed$(corrR, 2) + " R"
    if corrL = undefined or corrR = undefined
        corrTxt$ = "r = n/a"
    endif
    Text top: "no", "Measured output envelope, smoothed windowed RMS  (peak " + fixed$(outPeak, 3) + ")  —  against the predicted stack below: " + corrTxt$
    @railLabelAt: enX1, enX2, enY1, enY2, 7, 0.32, "RMS"

    # ----------------------------------------------------------
    # PANEL 4 — Morse score strip
    #
    # The 36-unit S-A-C-H-E-R score that generates the entry times was
    # documented only in the header comment.  Drawing it directly above the
    # layer timeline makes the letter-to-entry mapping visible: each voice
    # enters exactly where the previous letter ends.
    # ----------------------------------------------------------
    msName$[1] = "S"
    msName$[2] = "A"
    msName$[3] = "C"
    msName$[4] = "H"
    msName$[5] = "E"
    msName$[6] = "R"
    # 1 = dot, 3 = dash; symbols within a letter are separated by one unit
    msPat$[1] = "111"
    msPat$[2] = "13"
    msPat$[3] = "3131"
    msPat$[4] = "1111"
    msPat$[5] = "1"
    msPat$[6] = "131"

    Font size: 6
    Select outer viewport: 0, 8, 2.44, 3.02
    Select inner viewport: 0.65, 7.65, 2.60, 2.92
    Axes: 0, totalDuration, 0, 1
    Paint rectangle: "{0.975, 0.977, 0.985}", 0, totalDuration, 0, 1

    for i from 1 to 6
        msT = entry[i]
        msN = length(msPat$[i])
        for k from 1 to msN
            msSym$ = mid$(msPat$[i], k, 1)
            msLen = number(msSym$) * dot
            Paint rectangle: vCol$[i], msT, msT + msLen, 0.30, 0.72
            msT = msT + msLen + gap
        endfor
        # letter name above its span, and the boundary that starts the voice
        Colour: "{0.30, 0.30, 0.35}"
        Font size: 6
        Text: entry[i] + (msT - gap - entry[i]) / 2, "centre", 0.86, "half", "##" + msName$[i] + "##"
        if entry[i] > 0.0001
            Colour: "{0.55, 0.55, 0.60}"
            Dotted line
            Draw line: entry[i], 0, entry[i], 1
            Solid line
            Colour: "{0.35, 0.35, 0.40}"
            Font size: 5
            msLabY = 0.16
            if i > 1
                if entry[i] - entry[i - 1] < totalDuration * 0.08
                    msLabY = 0.06
                endif
            endif
            Text: entry[i], "left", msLabY, "half", " " + fixed$(entry[i], 2) + " s"
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Select inner viewport: 0.65, 7.65, 2.60, 2.92
    Axes: 0, totalDuration, 0, 1
    Marks bottom every: 1, tickScore, "no", "yes", "no"
    Text top: "no", "Morse score, S-A-C-H-E-R  (bars = dots and dashes; each letter boundary is the next voice's entry)"
    @railLabelAt: 0.65, 7.65, 2.60, 2.92, 6, 0.32, "Score"

    # ----------------------------------------------------------
    # PANEL 5 — Layer accumulation timeline
    # ----------------------------------------------------------
    Font size: 7
    Select outer viewport: 0, 8, 3.02, 3.98
    Select inner viewport: 0.65, 7.65, 3.12, 3.90
    rowH   = 1.0
    panelH = 6.0 * rowH
    Axes: 0, totalDuration, 0, panelH
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, 0, panelH

    for i from 1 to 6
        if entry[i] > 0.0001
            Colour: "{0.80, 0.80, 0.80}"
            Dotted line
            Draw line: entry[i], 0, entry[i], panelH
            Solid line
        endif
    endfor

    for i from 1 to 6
        row    = 6 - i
        barBot = row * rowH + 0.10
        barTop = (row + 1) * rowH - 0.10
        if entry[i] > 0.001
            Paint rectangle: "{0.88, 0.88, 0.88}", 0, entry[i], barBot, barTop
        endif
        Paint rectangle: vCol$[i], entry[i], totalDuration, barBot, barTop
        Colour: "White"
        Font size: 6
        # Gains are shown as rounded percentages: fixed$ ignores its precision
        # argument for very small numbers and would print a 17-digit 6e-17 for
        # a hard-panned voice's opposite channel.
        barLab$ = fixed$(targetFreq[i], 1) + " Hz   pan " + fixed$(panPos[i], 2)
        if activeDur[i] > totalDuration * 0.30
            barLab$ = barLab$ + "   L " + string$(round(panGainL[i] * 100)) + "\%  R " + string$(round(panGainR[i] * 100)) + "\% "
        endif
        Text: entry[i] + activeDur[i] * 0.50, "centre", barBot + rowH * 0.40, "half", barLab$
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Select inner viewport: 0.65, 7.65, 3.12, 3.90
    Axes: 0, totalDuration, 0, panelH
    Marks bottom every: 1, tickScore, "no", "yes", "no"
    for i from 1 to 6
        row = 6 - i
        One mark left: row * rowH + 0.5, "no", "yes", "no", pitchName$[i]
    endfor
    Font size: 7
    Select inner viewport: 0.65, 7.65, 3.12, 3.90
    Axes: 0, totalDuration, 0, panelH
    Text top: "no", "Layer accumulation  (grey = not yet entered, colour = sounding; entry times are marked on the Morse strip above)"
    @railLabelAt: 0.65, 7.65, 3.12, 3.90, 7, 0.32, "Voice"

    # ----------------------------------------------------------
    # PANEL 6 — Stereo accumulation
    #
    # v4.8 showed the score and the finished stereo with nothing in between.
    # This is the missing middle: each voice's fade-in envelope times its
    # constant-power pan gain, stacked, L upward and R downward, with the dry
    # signal as the grey base.  The visible asymmetry between the two halves
    # IS the pan field; where the two sides are equal, the field is centred.
    # ----------------------------------------------------------
    saX1 = 0.65
    saX2 = 7.65
    saY1 = 4.10
    saY2 = 4.96

    Font size: 6
    Select outer viewport: 0, 8, 3.98, 5.42

    nCols = 320
    colW  = totalDuration / nCols
    dryG  = dryMix * 0.707

    # y extent = the largest total the stack can reach on either side
    sumL = dryG
    sumR = dryG
    for i from 1 to 6
        sumL = sumL + wetMix * panGainL[i]
        sumR = sumR + wetMix * panGainR[i]
    endfor
    saMax = sumL
    if sumR > saMax
        saMax = sumR
    endif
    if saMax < 0.01
        saMax = 0.01
    endif
    saMax = saMax * 1.10
    @niceTickN: 2 * saMax, 6
    tickSa = niceTickN.t

    Select inner viewport: saX1, saX2, saY1, saY2
    Axes: 0, totalDuration, -saMax, saMax
    Paint rectangle: "{0.975, 0.977, 0.985}", 0, totalDuration, -saMax, saMax

    for c from 1 to nCols
        cT0 = (c - 1) * colW
        cT1 = c * colW
        cTm = (cT0 + cT1) / 2
        accL = 0
        accR = 0
        if dryG > 0
            Paint rectangle: "{0.80, 0.80, 0.82}", cT0, cT1, 0, dryG
            Paint rectangle: "{0.80, 0.80, 0.82}", cT0, cT1, -dryG, 0
            accL = dryG
            accR = dryG
        endif
        for i from 1 to 6
            # fade-in envelope actually applied to the layer at its entry
            if cTm < entry[i]
                env = 0
            elsif fadeDur > 0.001 and cTm < entry[i] + fadeDur
                env = 0.5 - 0.5 * cos(pi * (cTm - entry[i]) / fadeDur)
            else
                env = 1
            endif
            gL = wetMix * panGainL[i] * env
            gR = wetMix * panGainR[i] * env
            if gL > 0.0005
                Paint rectangle: vCol$[i], cT0, cT1, accL, accL + gL
                accL = accL + gL
            endif
            if gR > 0.0005
                Paint rectangle: vCol$[i], cT0, cT1, -accR - gR, -accR
                accR = accR + gR
            endif
        endfor
    endfor

    Font size: 6
    Select inner viewport: saX1, saX2, saY1, saY2
    Axes: 0, totalDuration, -saMax, saMax
    Colour: "{0.30, 0.30, 0.30}"
    Line width: 1
    Draw line: 0, 0, totalDuration, 0
    Font size: 6
    Colour: "{0.20, 0.45, 0.82}"
    Text: totalDuration * 0.012, "left", saMax * 0.80, "half", "##L##"
    Colour: "{0.82, 0.22, 0.18}"
    Text: totalDuration * 0.012, "left", -saMax * 0.80, "half", "##R##"
    Colour: "Black"
    Select inner viewport: saX1, saX2, saY1, saY2
    Axes: 0, totalDuration, -saMax, saMax
    Draw inner box

    Font size: 6
    Select inner viewport: saX1, saX2, saY1, saY2
    Axes: 0, totalDuration, -saMax, saMax
    Marks bottom every: 1, tickScore, "yes", "yes", "no"
    Marks left every: 1, tickSa, "yes", "yes", "no"

    Font size: 7
    Select inner viewport: saX1, saX2, saY1, saY2
    Axes: 0, totalDuration, -saMax, saMax
    Text bottom: "yes", "Score time (s)"
    Text top: "no", "Stereo accumulation  (fade envelope x constant-power pan gain, stacked; L above, R below; grey = dry)"
    @railLabelAt: saX1, saX2, saY1, saY2, 7, 0.32, "Stacked gain"

    # ----------------------------------------------------------
    # PANEL 7 — Pitch x Pan field
    #
    # Replaces v4.8's separate pan map and pitch ladder.  The ladder was on a
    # LINEAR Hz axis, where a semitone is 4 Hz at the bottom of the hexachord
    # and 7 Hz at the top, so four of the six labels collided; and its fMax
    # assumed A was the highest pitch when B is.  A semitone axis spaces the
    # set evenly by construction, and putting pan on x shows both structural
    # dimensions of the piece in one panel.
    # ----------------------------------------------------------
    ppX1 = 0.65
    ppX2 = 7.65
    ppY1 = 5.50
    ppY2 = 6.44

    Select outer viewport: 0, 8, 5.42, 6.92

    stMin = 0
    stMax = 0
    for i from 1 to 6
        stVal[i] = 12 * log10(targetFreq[i] / baseFreq) / log10(2)
        if i = 1
            stMin = stVal[i]
            stMax = stVal[i]
        endif
        if stVal[i] < stMin
            stMin = stVal[i]
        endif
        if stVal[i] > stMax
            stMax = stVal[i]
        endif
    endfor
    stLo = stMin - 1.8
    stHi = stMax + 1.8

    Font size: 6
    Select inner viewport: ppX1, ppX2, ppY1, ppY2
    Axes: -1.18, 1.18, stLo, stHi
    Paint rectangle: "{0.975, 0.977, 0.985}", -1.18, 1.18, stLo, stHi

    Colour: "{0.88, 0.89, 0.93}"
    Line width: 1
    for i from 1 to 6
        Draw line: -1.18, stVal[i], 1.18, stVal[i]
    endfor
    Colour: "{0.82, 0.82, 0.85}"
    Dotted line
    Draw line: 0, stLo, 0, stHi
    Solid line

    # Label side alternates with PITCH RANK, not with index: the hexachord
    # contains 2, 3 and 4 semitones from the root, which are too close to
    # separate vertically at this panel height, and at Pan_spread = 0 every
    # dot shares one x.  Alternating by rank guarantees that any two
    # neighbouring pitches end up on opposite sides of their dots.
    for i from 1 to 6
        ppRank[i] = 1
        for j from 1 to 6
            if stVal[j] < stVal[i]
                ppRank[i] = ppRank[i] + 1
            endif
        endfor
    endfor

    for i from 1 to 6
        Paint circle (mm): vCol$[i], panPos[i], stVal[i], 1.9
        Colour: "{0.20, 0.20, 0.24}"
        Font size: 6
        ppLab$ = "##" + pitchName$[i] + "##  " + fixed$(targetFreq[i], 1) + " Hz"
        ppSideRight = 1
        if ppRank[i] - 2 * floor(ppRank[i] / 2) = 0
            ppSideRight = 0
        endif
        # ...and a dot sitting on the frame is always labelled inward, so a
        # hard-panned voice's text cannot run outside the panel.
        if panPos[i] > 0.72
            ppSideRight = 0
        endif
        if panPos[i] < -0.72
            ppSideRight = 1
        endif
        if ppSideRight = 1
            Text: panPos[i] + 0.045, "left", stVal[i], "half", ppLab$
        else
            Text: panPos[i] - 0.045, "right", stVal[i], "half", ppLab$
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Select inner viewport: ppX1, ppX2, ppY1, ppY2
    Axes: -1.18, 1.18, stLo, stHi
    # Semitone marks, not Hz: the hexachord contains 2, 3 and 4 semitones from
    # the root, so per-pitch Hz labels collide at this panel height.  Each dot
    # already carries its own frequency.
    Marks left every: 1, 2, "yes", "yes", "no"
    One mark bottom: -1, "no", "yes", "no", "L"
    One mark bottom: -0.5, "no", "yes", "no", "-0.5"
    One mark bottom: 0, "no", "yes", "no", "C"
    One mark bottom: 0.5, "no", "yes", "no", "0.5"
    One mark bottom: 1, "no", "yes", "no", "R"

    Font size: 7
    Select inner viewport: ppX1, ppX2, ppY1, ppY2
    Axes: -1.18, 1.18, stLo, stHi
    Text bottom: "yes", "Pan position  (" + fixed$(pSpread*100, 0) + "\%  spread)"
    Text top: "no", "Pitch x pan field  —  SACHER hexachord on a semitone axis, placed in the stereo image"
    @railLabelAt: ppX1, ppX2, ppY1, ppY2, 7, 0.32, "Semitones from root"

    # ----------------------------------------------------------
    # SUMMARY
    # v4.8 drew two grey boxes on two different grids, the second of which
    # ("run parameters are reported in the Info window") carried no data.
    # ----------------------------------------------------------
    Font size: 7
    Select outer viewport: 0, 8, 6.96, 8.08
    Select inner viewport: 0.65, 7.65, 7.02, 8.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##  —  SACHER hexachord, Morse temporal structure"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.72, "left", 0.88, "half", "Preset: " + preset_name$

    Font size: 6
    Select inner viewport: 0.65, 7.65, 7.02, 8.02
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.35}"
    Text: 0.02, "left", 0.68, "half",
    ... "Source: " + soundName$ + "  (" + fixed$(originalDuration, 3) + " s)"
    ... + "   |   Target register: MIDI " + string$(midiNote) + " (" + noteName$ + " = " + fixed$(baseFreq, 2) + " Hz)"
    ... + "   |   Assumed source pitch: MIDI " + string$(sourceMidi) + " (" + fixed$(sourcePitchFreq, 2) + " Hz)"
    Text: 0.02, "left", 0.50, "half",
    ... "dot=" + fixed$(dot, 4) + " s   dash=" + fixed$(dash, 4) + " s   score = 36 units = " + fixed$(totalDuration, 3) + " s"
    ... + "   |   Wet " + fixed$(wetMix*100, 0) + "\%  / dry " + fixed$(dryMix*100, 0) + "\%  "
    ... + "   |   Pan spread " + fixed$(pSpread*100, 0) + "\%  "
    ... + "   |   Fade " + fixed$(fadeDur*1000, 1) + " ms"
    ... + "   |   Loop " + string$(loopShort)
    ... + "   |   SR " + string$(samplingFrequency) + " Hz"
    Text: 0.02, "left", 0.32, "half",
    ... "Layers (entry s / Hz / pan):  "
    ... + pitchName$[1] + " " + fixed$(entry[1],2) + "/" + fixed$(targetFreq[1],1) + "/" + fixed$(panPos[1],2) + "   "
    ... + pitchName$[2] + " " + fixed$(entry[2],2) + "/" + fixed$(targetFreq[2],1) + "/" + fixed$(panPos[2],2) + "   "
    ... + pitchName$[3] + " " + fixed$(entry[3],2) + "/" + fixed$(targetFreq[3],1) + "/" + fixed$(panPos[3],2) + "   "
    ... + pitchName$[4] + " " + fixed$(entry[4],2) + "/" + fixed$(targetFreq[4],1) + "/" + fixed$(panPos[4],2) + "   "
    ... + pitchName$[5] + " " + fixed$(entry[5],2) + "/" + fixed$(targetFreq[5],1) + "/" + fixed$(panPos[5],2) + "   "
    ... + pitchName$[6] + " " + fixed$(entry[6],2) + "/" + fixed$(targetFreq[6],1) + "/" + fixed$(panPos[6],2)
    Text: 0.02, "left", 0.13, "half",
    ... "Output peak " + fixed$(outPeak, 4) + "   |   duration " + fixed$(totalDuration, 3) + " s   |   stereo"

    Font size: 6
    Select inner viewport: 0.65, 7.65, 7.02, 8.02
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Save as / Copy from the Picture window exports the CURRENT viewport
    # selection, so the script must end on the whole canvas or the export
    # comes out cropped to the last panel drawn.
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH
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

# ============================================================
# VISUALIZATION HELPERS
# ============================================================

# Text left: / Text right: position a rotated panel label against whatever
# drawing frame is current, so panels of different widths get their names at
# different x — in v4.8 the five rail labels sat at four different positions.
# Placing them at an ABSOLUTE page position keeps the rail straight.
# Vertical alignment must be "bottom", not "half": "half" anchors the glyph
# bounding box, so a descender shifts that one label off the rail.
procedure railLabelAt: .x1, .x2, .y1, .y2, .size, .targetIn, .label$
    .xn = (.targetIn - .x1) / (.x2 - .x1)
    Font size: .size
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: .xn, "centre", 0.5, "bottom", "Helvetica", .size, "90", .label$
endproc

# Axis tick spacing: the largest 1/2/5 x 10^k step that still gives roughly
# the requested number of divisions across the span.  Short panels need a
# coarser step or the numbers stack on top of each other.
procedure niceTick: .span
    @niceTickN: .span, 8
    .t = niceTickN.t
endproc

procedure niceTickN: .span, .divisions
    if .span <= 0
        .t = 1
    else
        .raw  = .span / .divisions
        .expo = floor(log10(.raw))
        .base = .raw / 10 ^ .expo
        if .base < 1.5
            .m = 1
        elsif .base < 3.5
            .m = 2
        elsif .base < 7.5
            .m = 5
        else
            .m = 10
        endif
        .t = .m * 10 ^ .expo
    endif
endproc


# Pearson r from running sums, so the measured envelope and the predicted
# stack can be compared without a second pass over the audio.
procedure pearson: .n, .sx, .sy, .sxy, .sx2, .sy2
    .num = .n * .sxy - .sx * .sy
    .d1  = .n * .sx2 - .sx * .sx
    .d2  = .n * .sy2 - .sy * .sy
    if .d1 <= 0 or .d2 <= 0
        .r = undefined
    else
        .r = .num / sqrt(.d1 * .d2)
    endif
endproc
