# ============================================================
# Praat AudioTools - Whisper Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LPC-based whisper resynthesis. Each input channel is analysed with LPC,
#   Gaussian noise is filtered by that channel's LPC spectral envelope, and
#   the result is shaped by the source intensity contour. A time-varying
#   crossfade morphs between the unmodified dry signal and the whisper target.
#
# Important:
#   This is creative whisper resynthesis, not a physiological whisper model.
#   The LPC filter preserves a time-varying vocal-tract spectral envelope;
#   the periodic excitation is replaced partly or fully by noise.
#
# Changelog v1.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v1.3:
#   - Dry path is now the unmodified source; LPC analysis no longer normalizes it.
#   - Preserves arbitrary channel count and the source start time.
#   - Internal processing is zero-based, fixing non-zero-start LPC domain errors.
#   - Breathiness now accepts the documented 0..1 range, including 0.
#   - Replaced absolute IntensityTier + forced peak scaling with a relative
#     dB envelope and Multiply "no"; gate values use -300 dB for true silence.
#   - Added reproducible random seed, gate range, and attenuation-only safety peak.
#   - Renamed High_frequency_boost to Brightness_adjust_dB. 0 dB preserves the
#     v1.2 reference EQ; presets map to the same relative brightness offsets.
#   - Spectrum EQ uses To Spectrum "no", avoiding power-of-two padding/cropping.
#   - Visualization updated to the AudioTools house style.
# ============================================================

form Whisper Morph v1.4
    optionmenu Preset: 1
        option Custom
        option Gentle Whisper
        option Breathy Whisper
        option Harsh Whisper
        option ASMR Style
    comment === Morph Type ===
    optionmenu Morph_type: 1
        option Dry to Wet (original -> whisper)
        option Wet to Dry (whisper -> original)
        option Dry-Wet-Dry (original -> whisper -> original)
        option Wet-Dry-Wet (whisper -> original -> whisper)
        option Full Whisper (no morph)
    comment === Whisper Parameters ===
    positive LPC_order_factor 1.0
    comment (1.0 = standard, higher = more LPC detail)
    real Breathiness 0.8
    comment (0 = tonal source, 1 = full noise excitation)
    real Brightness_adjust_dB 0.0
    comment (0 = v1.2 reference EQ; positive = brighter)
    positive Gate_range_dB 40
    integer Random_seed 0
    comment (0 = unpredictable; non-zero = reproducible noise)
    comment === Morph Curve ===
    optionmenu Morph_curve: 1
        option Linear
        option Smooth (cosine)
        option Exponential
    comment === Output ===
    real Safety_peak 0.99
    comment (0 = off; otherwise attenuation only, never boosts)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    lPC_order_factor = 0.9
    breathiness = 0.7
    brightness_adjust_dB = -2.0
    gate_range_dB = 40
    presetName$ = "Gentle Whisper"
elsif preset = 3
    lPC_order_factor = 1.0
    breathiness = 1.0
    brightness_adjust_dB = 2.0
    gate_range_dB = 40
    presetName$ = "Breathy Whisper"
elsif preset = 4
    lPC_order_factor = 1.2
    breathiness = 0.9
    brightness_adjust_dB = 4.0
    gate_range_dB = 40
    presetName$ = "Harsh Whisper"
elsif preset = 5
    lPC_order_factor = 1.1
    breathiness = 0.6
    brightness_adjust_dB = -3.0
    gate_range_dB = 35
    presetName$ = "ASMR Style"
else
    presetName$ = "Custom"
endif

# Parameter validation
if breathiness < 0
    breathiness = 0
endif
if breathiness > 1
    breathiness = 1
endif
if lPC_order_factor < 0.5
    lPC_order_factor = 0.5
endif
if lPC_order_factor > 2.0
    lPC_order_factor = 2.0
endif
if brightness_adjust_dB < -18
    brightness_adjust_dB = -18
endif
if brightness_adjust_dB > 18
    brightness_adjust_dB = 18
endif
if gate_range_dB < 10
    gate_range_dB = 10
endif
if gate_range_dB > 100
    gate_range_dB = 100
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

if morph_type = 1
    morphType$ = "Dry to Wet"
elsif morph_type = 2
    morphType$ = "Wet to Dry"
elsif morph_type = 3
    morphType$ = "Dry-Wet-Dry"
elsif morph_type = 4
    morphType$ = "Wet-Dry-Wet"
else
    morphType$ = "Full Whisper"
endif

if morph_curve = 1
    curve$ = "Linear"
elsif morph_curve = 2
    curve$ = "Smooth"
else
    curve$ = "Exponential"
endif

# ============================================================
# INPUT VALIDATION / ZERO-BASED WORK COPY
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
xminOriginal = Get start time
originalPeak = Get absolute extremum: 0, 0, "None"
originalIntensity = Get intensity (dB)

if originalPeak <= 0
    exitScript: "Input is silent."
endif
if duration < 0.1
    exitScript: "Sound too short (min 0.1 s)."
endif

# Work on an exact copy whose domain starts at zero. This avoids domain
# mismatches between LPC objects and synthesized noise while keeping the dry
# samples untouched.
selectObject: originalID
workAll = Copy: "wm_work"
if xminOriginal <> 0
    selectObject: workAll
    Shift times by: -xminOriginal
endif

# LPC order follows the original rule, with safe bounds.
lpcOrder = round((2 + sampleRate / 1000) * lPC_order_factor)
lpcOrder = max(10, min(50, lpcOrder))

writeInfoLine: "=== Whisper Morph v1.4 ==="
appendInfoLine: "Input: ", originalName$, " | ", numChannels, " ch | ", fixed$(sampleRate, 0), " Hz"
appendInfoLine: "Duration: ", fixed$(duration, 3), " s | start ", fixed$(xminOriginal, 3), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Morph: ", morphType$, " | curve: ", curve$
appendInfoLine: "LPC order: ", lpcOrder
appendInfoLine: "Breathiness: ", fixed$(breathiness, 2), " | brightness adjust: ", fixed$(brightness_adjust_dB, 1), " dB"
appendInfoLine: "Gate range: ", fixed$(gate_range_dB, 1), " dB"
if random_seed <> 0
    appendInfoLine: "Random seed: ", random_seed
else
    appendInfoLine: "Random seed: unpredictable"
endif
appendInfoLine: ""

# ============================================================
# BUILD WHISPER TARGET, CHANNEL BY CHANNEL
# ============================================================
wetAll = Create Sound from formula: "wm_wetall", numChannels, 0, duration, sampleRate, "0"

if random_seed <> 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# v1.2 reference EQ, expressed as brightness offset around the old default.
gMid = 12 + brightness_adjust_dB
gHigh = 24 + brightness_adjust_dB

for ch from 1 to numChannels
    selectObject: workAll
    chanWork = Extract one channel: ch
    Rename: "wm_chan"
    channelPeak = Get absolute extremum: 0, 0, "None"

    if channelPeak <= 1e-15
        # Silent channel remains silent.
        wetCh = Copy: "wm_wetch"
    else
        channelIntensity = Get intensity (dB)

        # LPC vocal-tract model from the unnormalized channel. Burg LPC is
        # scale-invariant, so changing source gain is unnecessary.
        selectObject: chanWork
        lpcObj = To LPC (burg): lpcOrder, 0.025, 0.005, 50

        # Noise excitation in the same time domain and sample rate.
        noiseSource = Create Sound from formula: "wm_noise", 1, 0, duration, sampleRate, "randomGauss(0, 0.5)"
        selectObject: noiseSource
        plusObject: lpcObj
        whisperRaw = Filter: "yes"

        # Crisp whisper EQ. Brightness_adjust_dB is an offset around the v1.2
        # reference curve, so 0 dB preserves the old default spectral balance.
        selectObject: whisperRaw
        whisperSpec = To Spectrum: "no"
        Formula: "self * 10 ^ ((if x < 354 then -24 else if x < 707 then 'gMid:8' else if x < 2828 then 'gHigh:8' else if x < 11314 then 'gMid:8' else -6 fi fi fi fi) / 20)"
        whisperEQ = To Sound

        # Relative source envelope. 0 dB means peak envelope; quieter frames
        # carry negative relative dB. Gated frames use -300 dB rather than 0 dB.
        selectObject: chanWork
        intensityObj = To Intensity: 100, 0.01, "yes"
        maxInt = Get maximum: 0, 0, "Parabolic"
        Formula: "if self < 'maxInt:8' - 'gate_range_dB:8' then -300 else self - 'maxInt:8' fi"
        envTier = Down to IntensityTier

        selectObject: whisperEQ
        plusObject: envTier
        whisperShaped = Multiply: "no"

        # Match the full-noise whisper target to the dry channel RMS intensity.
        selectObject: whisperShaped
        shapedPeak = Get absolute extremum: 0, 0, "None"
        if shapedPeak > 1e-15 and channelIntensity <> undefined
            Scale intensity: channelIntensity
        endif

        # Breathiness blends the noise-excited target with the unchanged tonal
        # source. Special-case 0 for an exact tonal endpoint.
        if breathiness <= 0
            selectObject: chanWork
            wetCh = Copy: "wm_wetch"
        else
            selectObject: whisperShaped
            wetCh = Copy: "wm_wetch"
            if breathiness < 1
                Formula: "self * 'breathiness:8' + object['chanWork:0', 1, col] * (1 - 'breathiness:8')"
                blendPeak = Get absolute extremum: 0, 0, "None"
                if blendPeak > 1e-15 and channelIntensity <> undefined
                    Scale intensity: channelIntensity
                endif
            endif
        endif

        removeObject: lpcObj, noiseSource, whisperRaw, whisperSpec, whisperEQ
        removeObject: intensityObj, envTier, whisperShaped
    endif

    # Copy this wet target into the matching output channel.
    selectObject: wetAll
    Formula (part): 0, duration, ch, ch, "object['wetCh:0', 1, col]"
    removeObject: chanWork, wetCh
endfor

if random_seed <> 0
    random_initializeSafelyAndUnpredictably ()
endif

# ============================================================
# MORPH DRY <-> WHISPER TARGET
# ============================================================
morphedSound = Create Sound from formula: "wm_morphed", numChannels, 0, duration, sampleRate, "0"
durStr$ = fixed$(duration, 10)

if morph_type = 5
    selectObject: morphedSound
    Formula: "object['wetAll:0', row, col]"
else
    if morph_type = 1
        mixFormula$ = "(x/" + durStr$ + ")"
    elsif morph_type = 2
        mixFormula$ = "(1 - x/" + durStr$ + ")"
    elsif morph_type = 3
        halfDur$ = fixed$(duration / 2, 10)
        mixFormula$ = "(if x < " + halfDur$ + " then x/" + halfDur$ + " else 1 - (x - " + halfDur$ + ")/" + halfDur$ + " fi)"
    else
        halfDur$ = fixed$(duration / 2, 10)
        mixFormula$ = "(if x < " + halfDur$ + " then 1 - x/" + halfDur$ + " else (x - " + halfDur$ + ")/" + halfDur$ + " fi)"
    endif

    if morph_curve = 1
        finalMixFormula$ = mixFormula$
    elsif morph_curve = 2
        finalMixFormula$ = "(0.5 - 0.5 * cos(pi * " + mixFormula$ + "))"
    else
        finalMixFormula$ = "(" + mixFormula$ + ")^2"
    endif

    selectObject: morphedSound
    Formula: "object['workAll:0', row, col] * (1 - " + finalMixFormula$ + ") + object['wetAll:0', row, col] * " + finalMixFormula$
endif

# Return the source time domain.
selectObject: morphedSound
if xminOriginal <> 0
    Shift times by: xminOriginal
endif
Rename: originalName$ + "_whispermorph"
finalName$ = selected$("Sound")

# Attenuation-only safety limiter.
finalPeakBeforeSafety = Get absolute extremum: 0, 0, "None"
if safety_peak > 0 and finalPeakBeforeSafety > safety_peak
    Scale peak: safety_peak
    safetyApplied = 1
else
    safetyApplied = 0
endif
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_visualization
    selectObject: originalID
    if numChannels > 1
        vizIn = Convert to mono
    else
        vizIn = Copy: "wm_vizin"
    endif
    selectObject: morphedSound
    if numChannels > 1
        vizOut = Convert to mono
    else
        vizOut = Copy: "wm_vizout"
    endif

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    # Title
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Whisper Morph v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.72, 1.48
    Select inner viewport: 0.55, 7.7, 0.80, 1.42
    selectObject: vizIn
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.52, 2.28
    Select inner viewport: 0.55, 7.7, 1.60, 2.22
    selectObject: vizOut
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Paired spectrograms
    maxVizHz = min(8000, sampleRate / 2)
    Select outer viewport: 0, 4, 2.48, 4.02
    Select inner viewport: 0.55, 3.75, 2.58, 3.94
    selectObject: vizIn
    specIn = To Spectrogram: 0.03, maxVizHz, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, maxVizHz, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input spectrogram"
    Text left: "yes", "Hz"

    Select outer viewport: 4, 8, 2.48, 4.02
    Select inner viewport: 4.25, 7.7, 2.58, 3.94
    selectObject: vizOut
    specOut = To Spectrogram: 0.03, maxVizHz, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, maxVizHz, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output spectrogram"

    # Morph curve
    Select outer viewport: 0, 8, 4.14, 5.26
    Select inner viewport: 0.55, 7.7, 4.24, 5.18
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 0.5, duration, 0.5
    Solid line
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 2
    nPlot = 200
    prevT = 0
    if morph_type = 1 or morph_type = 3
        prevLin = 0
    else
        prevLin = 1
    endif
    if morph_type = 5
        prevLin = 1
    endif
    if morph_curve = 1 or morph_type = 5
        prevM = prevLin
    elsif morph_curve = 2
        prevM = 0.5 - 0.5 * cos(pi * prevLin)
    else
        prevM = prevLin ^ 2
    endif
    for q from 1 to nPlot
        tt = duration * q / nPlot
        tn = tt / duration
        if morph_type = 1
            ml = tn
        elsif morph_type = 2
            ml = 1 - tn
        elsif morph_type = 3
            if tn < 0.5
                ml = 2 * tn
            else
                ml = 2 * (1 - tn)
            endif
        elsif morph_type = 4
            if tn < 0.5
                ml = 1 - 2 * tn
            else
                ml = 2 * (tn - 0.5)
            endif
        else
            ml = 1
        endif
        if morph_curve = 1 or morph_type = 5
            mm = ml
        elsif morph_curve = 2
            mm = 0.5 - 0.5 * cos(pi * ml)
        else
            mm = ml ^ 2
        endif
        Draw line: prevT, prevM, tt, mm
        prevT = tt
        prevM = mm
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Whisper mix"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 5.46, 6.27
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.76, "half", "##Whisper target##  LPC " + string$(lpcOrder) + " | breathiness " + fixed$(breathiness, 2) + " | brightness " + fixed$(brightness_adjust_dB, 1) + " dB"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.46, "half", "Gate " + fixed$(gate_range_dB, 1) + " dB | " + string$(numChannels) + " ch | " + fixed$(sampleRate, 0) + " Hz | start " + fixed$(xminOriginal, 3) + " s"
    Text: 0.02, "left", 0.20, "half", "Peak " + fixed$(originalPeak, 4) + " -> " + fixed$(finalPeak, 4) + " | safety=" + string$(safetyApplied)

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizIn, vizOut, specIn, specOut
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# CLEANUP / OUTPUT
# ============================================================
removeObject: workAll, wetAll

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Channels: ", numChannels, " | start: ", fixed$(xminOriginal, 3), " s"
appendInfoLine: "Peak: ", fixed$(originalPeak, 4), " -> ", fixed$(finalPeak, 4)
if safetyApplied
    appendInfoLine: "Safety attenuation applied."
endif

selectObject: morphedSound
if play_result
    Play
endif