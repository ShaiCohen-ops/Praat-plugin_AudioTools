# ============================================================
# Praat AudioTools - Jitter-Shimmer Formant Mapping
# Author: Shai Cohen
# Version: 3.0 (2026) - Spectral-Envelope Landmark Edition
# License: MIT License
#
# Concept:
#   Jitter and shimmer are measured from a robust mono analysis source,
#   then mapped to two STATIC spectral-envelope transformations:
#     shimmer -> F1-F2 target shift
#     jitter  -> F3-F5 target shift
#
#   Praat formants are analysis LANDMARKS only. They are never converted
#   to LPC poles for resynthesis. The original complex spectrum of each
#   channel is multiplied by a smooth real gain curve, preserving phase.
#
#   Optional pitch shift is a separate stage and never changes the
#   formant-landmark architecture.
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select one or more Sound objects first."
endif

form Jitter Shimmer Formant Mapping v3.0
    comment === PRESETS ===
    optionmenu Preset 1
        option Modal (Subtle)
        option Breathy (Brighter)
        option Creaky (Darker)
        option Tense (Sharp)
        option Relaxed (Smooth)
        option Custom

    comment === MAPPING INTENSITY ===
    positive Global_intensity 1.0

    comment === CUSTOM WEIGHTS (0 for no effect) ===
    real Shimmer_to_F1F2 0.3
    real Jitter_to_F3F5 0.3

    comment === PITCH CONTROL ===
    boolean Auto_detect_pitch_range 1
    positive Manual_pitch_floor_Hz 75
    positive Manual_pitch_ceiling_Hz 600
    boolean Apply_pitch_shift 0

    comment === OUTPUT / VISUALIZATION ===
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Keep_intermediates 0

    comment === SPECTRAL-ENVELOPE ENGINE ===
    positive Max_formant_hz 5500
    positive Envelope_width_scale 1.0
    positive Envelope_strength_dB 15
    real Dry_wet_mix 1.0
    boolean Require_formant_confidence 1
    optionmenu Output_level_mode 1
        option Natural level
        option Safety ceiling
        option Peak normalize
    positive Ceiling_peak 0.95
endform

# ------------------------------------------------------------
# Validate / clamp user parameters
# ------------------------------------------------------------
if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif
if envelope_width_scale < 0.2
    envelope_width_scale = 0.2
elsif envelope_width_scale > 4
    envelope_width_scale = 4
endif
if envelope_strength_dB < 0.1
    envelope_strength_dB = 0.1
elsif envelope_strength_dB > 36
    envelope_strength_dB = 36
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    ceiling_peak = 0.95
endif
if manual_pitch_floor_Hz <= 0 or manual_pitch_ceiling_Hz <= manual_pitch_floor_Hz
    exitScript: "Need 0 < Manual_pitch_floor_Hz < Manual_pitch_ceiling_Hz."
endif

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
pitch_multiplier = 1.0
s_weight_low = shimmer_to_F1F2
j_weight_high = jitter_to_F3F5
presetName$ = "Custom"

if preset = 1
    # Modal: subtle and stable
    s_weight_low = 0.10
    j_weight_high = 0.10
    pitch_multiplier = 1.00
    envelope_strength_dB = 10
    envelope_width_scale = 1.10
    presetName$ = "Modal"
elsif preset = 2
    # Breathy: shimmer opens low spectral landmarks
    s_weight_low = 0.50
    j_weight_high = 0.30
    pitch_multiplier = 1.08
    envelope_strength_dB = 16
    envelope_width_scale = 1.25
    presetName$ = "Breathy"
elsif preset = 3
    # Creaky: pull landmarks downward
    s_weight_low = -0.40
    j_weight_high = -0.20
    pitch_multiplier = 0.92
    envelope_strength_dB = 15
    envelope_width_scale = 1.15
    presetName$ = "Creaky"
elsif preset = 4
    # Tense: stronger high-formant action
    s_weight_low = 0.20
    j_weight_high = 0.60
    pitch_multiplier = 1.05
    envelope_strength_dB = 19
    envelope_width_scale = 0.85
    presetName$ = "Tense"
elsif preset = 5
    # Relaxed: broad, gentle redistribution
    s_weight_low = 0.30
    j_weight_high = -0.20
    pitch_multiplier = 0.98
    envelope_strength_dB = 12
    envelope_width_scale = 1.45
    presetName$ = "Relaxed"
endif

sounds# = selected#("Sound")
numSounds = size(sounds#)
resultSounds# = zero#(numSounds)

# Visualization defaults (also safe for bypass / silent first input)
vizHaveLandmarks = 0
vizJitter = 0
vizShimmer = 0
vizLowShift = 1
vizHighShift = 1
vizConfidence = 0
for fn from 1 to 5
    vizOld_'fn' = undefined
    vizTarget_'fn' = undefined
endfor

clearinfo
writeInfoLine: "=== Jitter-Shimmer Formant Mapping v3.0 ==="
appendInfoLine: "Engine: static spectral-envelope warp; original phase preserved"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Selected sounds: ", numSounds
appendInfoLine: ""

# ============================================================
# MAIN LOOP
# ============================================================
for current from 1 to numSounds
    selectObject: sounds#[current]
    originalName$ = selected$("Sound")
    originalDur = Get total duration
    originalSR = Get sampling frequency
    originalXmin = Get start time
    numChannels = Get number of channels
    nyquist = originalSR / 2

    appendInfoLine: "------------------------------------------------------------"
    appendInfoLine: "[", current, "/", numSounds, "] ", originalName$
    appendInfoLine: "Channels: ", numChannels, " | SR: ", fixed$(originalSR, 0), " Hz"

    # Exact dry bypass. Output-level mode is intentionally ignored here.
    if dry_wet_mix = 0 or ((global_intensity = 0 or (abs(s_weight_low) < 0.000000001 and abs(j_weight_high) < 0.000000001)) and not apply_pitch_shift)
        selectObject: sounds#[current]
        resultID = Copy: originalName$ + "_JitterShimmer_Bypass"
        resultSounds#[current] = resultID
        appendInfoLine: "Exact bypass."
        if play_result
            selectObject: resultID
            Play
        endif
    else
        # Work at t=0 so spectral and pitch operations have simple domains.
        selectObject: sounds#[current]
        workSound = Copy: "jsfm_work"
        selectObject: workSound
        Shift times by: -originalXmin

        # ------------------------------------------------------------
        # Pick a robust analysis source without changing output channels.
        # ------------------------------------------------------------
        if numChannels = 1
            selectObject: workSound
            analysisSound = Copy: "jsfm_analysis"
            analysisSource$ = "mono"
        else
            bestRms = -1
            pickCh = 1
            for ch from 1 to numChannels
                selectObject: workSound
                probe = Extract one channel: ch
                r = Get root-mean-square: 0, 0
                removeObject: probe
                if r > bestRms
                    bestRms = r
                    pickCh = ch
                endif
            endfor
            selectObject: workSound
            analysisSound = Extract one channel: pickCh
            analysisSource$ = "loudest channel " + string$(pickCh)
        endif

        selectObject: analysisSound
        analysisRMS = Get root-mean-square: 0, 0
        if analysisRMS = undefined or analysisRMS < 0.0000001
            removeObject: analysisSound, workSound
            selectObject: sounds#[current]
            resultID = Copy: originalName$ + "_JitterShimmer_SilenceBypass"
            resultSounds#[current] = resultID
            appendInfoLine: "Silent/near-silent analysis source -> bypass."
        else
            appendInfoLine: "Analysis source: ", analysisSource$

            # ------------------------------------------------------------
            # Pitch range + jitter/shimmer measurement
            # ------------------------------------------------------------
            pitchFloor = manual_pitch_floor_Hz
            pitchCeiling = manual_pitch_ceiling_Hz

            if auto_detect_pitch_range
                selectObject: analysisSound
                pitchWide = To Pitch (cc): 0, 50, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, min(800, nyquist - 50)
                selectObject: pitchWide
                q10 = Get quantile: 0, 0, 0.10, "Hertz"
                q90 = Get quantile: 0, 0, 0.90, "Hertz"
                if q10 <> undefined and q90 <> undefined and q90 > q10
                    pitchFloor = max(40, q10 * 0.8)
                    pitchCeiling = min(min(800, nyquist - 50), q90 * 1.3)
                endif
                removeObject: pitchWide
            endif
            if pitchCeiling <= pitchFloor
                pitchFloor = manual_pitch_floor_Hz
                pitchCeiling = min(manual_pitch_ceiling_Hz, nyquist - 50)
            endif

            selectObject: analysisSound
            pitch = To Pitch (cc): 0, pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling
            selectObject: pitch
            medianPitch = Get quantile: 0, 0, 0.5, "Hertz"

            jitterVal = undefined
            shimmerVal = undefined
            pointProcess = 0
            if medianPitch <> undefined
                selectObject: analysisSound
                plusObject: pitch
                pointProcess = To PointProcess (cc)

                selectObject: analysisSound
                plusObject: pitch
                plusObject: pointProcess
                voiceReport$ = Voice report: 0, 0, pitchFloor, pitchCeiling, 1.3, 1.6, 0.03, 0.45
                @extractNumber: voiceReport$, "Jitter (local): "
                jitterVal = extractNumber.result
                @extractNumber: voiceReport$, "Shimmer (local): "
                shimmerVal = extractNumber.result
            endif

            # Fail safe: do not invent a voice-quality measurement.
            if jitterVal = undefined or jitterVal < 0
                jitterVal = 0
            endif
            if shimmerVal = undefined or shimmerVal < 0
                shimmerVal = 0
            endif

            effJitter = jitterVal * global_intensity
            effShimmer = shimmerVal * global_intensity
            log10_6 = 0.778151
            log10_11 = 1.041393
            jitterNorm = log10(1 + effJitter) / log10_6
            shimmerNorm = log10(1 + effShimmer) / log10_11
            lowFormantShift = 1.0 + shimmerNorm * s_weight_low
            highFormantShift = 1.0 + jitterNorm * j_weight_high
            lowFormantShift = max(0.5, min(2.0, lowFormantShift))
            highFormantShift = max(0.5, min(2.0, highFormantShift))

            appendInfoLine: "Jitter: ", fixed$(jitterVal, 3), "% | Shimmer: ", fixed$(shimmerVal, 3), "%"
            appendInfoLine: "F1-F2 ratio: ", fixed$(lowFormantShift, 3), " | F3-F5 ratio: ", fixed$(highFormantShift, 3)

            # ------------------------------------------------------------
            # Robust static formant landmarks
            # ------------------------------------------------------------
            safeMaxFormant = min(max_formant_hz, (nyquist - 50) / 1.22)
            if safeMaxFormant < 1000
                safeMaxFormant = 1000
            endif
            max_formants = 5
            time_step_s = 0.005
            window_length_s = 0.030
            pre_emphasis = 35

            selectObject: analysisSound
            formantPath = To FormantPath (burg): time_step_s, max_formants, safeMaxFormant, window_length_s, pre_emphasis, 0.05, 4
            formantObj = Extract Formant

            for fn from 1 to max_formants
                selectObject: formantObj
                formant_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.5
            endfor

            validFormants = 0
            firstLandmark = undefined
            lastLandmark = undefined
            for fn from 1 to max_formants
                if formant_'fn' <> undefined and formant_'fn' > 0
                    validFormants = validFormants + 1
                    if firstLandmark = undefined
                        firstLandmark = formant_'fn'
                    endif
                    lastLandmark = formant_'fn'
                endif
            endfor

            confidenceOK = 1
            if validFormants < 2
                confidenceOK = 0
            elsif lastLandmark - firstLandmark < 600
                confidenceOK = 0
            endif

            doWarp = 1
            if require_formant_confidence and confidenceOK = 0
                doWarp = 0
                appendInfoLine: "Formant confidence gate: narrow/invalid landmark set -> spectral warp bypass."
            elsif validFormants < 1
                doWarp = 0
                appendInfoLine: "No usable formant landmarks -> spectral warp bypass."
            endif

            # ------------------------------------------------------------
            # Build target map and one static gain curve.
            # ------------------------------------------------------------
            expr$ = ""
            terms = 0
            region_fraction = 0.24
            region_floor_1 = 180
            region_floor_2 = 260
            region_floor_3 = 360
            region_floor_4 = 450
            region_floor_5 = 550

            for fn from 1 to max_formants
                old_'fn' = formant_'fn'
                target_'fn' = formant_'fn'
                active_'fn' = 0
                if formant_'fn' <> undefined and formant_'fn' > 0
                    if fn <= 2
                        ratioHere = lowFormantShift
                    else
                        ratioHere = highFormantShift
                    endif
                    target_'fn' = formant_'fn' * ratioHere
                    target_'fn' = max(80, min(nyquist - 80, target_'fn'))
                    if abs(target_'fn' - old_'fn') > 0.5
                        active_'fn' = 1
                    endif
                endif

                if doWarp and active_'fn' = 1
                    if fn = 1
                        floorW = region_floor_1
                    elsif fn = 2
                        floorW = region_floor_2
                    elsif fn = 3
                        floorW = region_floor_3
                    elsif fn = 4
                        floorW = region_floor_4
                    else
                        floorW = region_floor_5
                    endif
                    width = max(floorW, old_'fn' * region_fraction) * envelope_width_scale
                    width = max(90, min(1400, width))
                    if terms > 0
                        expr$ = expr$ + " + "
                    endif
                    expr$ = expr$ + fixed$(envelope_strength_dB, 4) + " * (exp(-0.5*((x-" +
                        ... fixed$(target_'fn', 3) + ")/" + fixed$(width, 3) + ")^2) - exp(-0.5*((x-" +
                        ... fixed$(old_'fn', 3) + ")/" + fixed$(width, 3) + ")^2))"
                    terms = terms + 1
                endif
            endfor

            if terms = 0
                doWarp = 0
            endif
            shapeLimit$ = fixed$(envelope_strength_dB, 4)

            appendInfoLine: "Landmark targets:"
            for fn from 1 to max_formants
                if old_'fn' <> undefined
                    appendInfoLine: "  F", fn, ": ", fixed$(old_'fn', 1), " -> ", fixed$(target_'fn', 1), " Hz"
                endif
            endfor

            # Save first-sound visualization values before cleanup.
            if current = 1
                vizHaveLandmarks = 1
                vizJitter = jitterVal
                vizShimmer = shimmerVal
                vizLowShift = lowFormantShift
                vizHighShift = highFormantShift
                vizConfidence = confidenceOK
                for fn from 1 to max_formants
                    vizOld_'fn' = old_'fn'
                    vizTarget_'fn' = target_'fn'
                endfor
            endif

            # ------------------------------------------------------------
            # Process each channel independently.
            # ------------------------------------------------------------
            for ch from 1 to numChannels
                if numChannels = 1
                    selectObject: workSound
                    dryCh[ch] = Copy: "jsfm_dry"
                else
                    selectObject: workSound
                    dryCh[ch] = Extract one channel: ch
                endif

                if doWarp
                    @spectralWarpChannel: dryCh[ch]
                    wetCh[ch] = spectralWarpChannel.result
                else
                    selectObject: dryCh[ch]
                    wetCh[ch] = Copy: "jsfm_nowarp"
                endif

                # Optional pitch stage is independent from the formant warp.
                if apply_pitch_shift and medianPitch <> undefined and abs(pitch_multiplier - 1) > 0.000001
                    selectObject: wetCh[ch]
                    manip = To Manipulation: 0.01, pitchFloor, pitchCeiling
                    selectObject: manip
                    pt = Extract pitch tier
                    selectObject: pt
                    Formula: "self * " + string$(pitch_multiplier)
                    selectObject: manip
                    plusObject: pt
                    Replace pitch tier
                    selectObject: manip
                    shifted = Get resynthesis (overlap-add)
                    removeObject: wetCh[ch], manip, pt
                    wetCh[ch] = shifted
                endif

                if dry_wet_mix < 1
                    selectObject: wetCh[ch]
                    Formula: "self*" + string$(dry_wet_mix) + " + object[" + string$(dryCh[ch]) + ",1,col]*" + string$(1-dry_wet_mix)
                endif
            endfor

            if numChannels = 1
                selectObject: wetCh[1]
                finalOutput = Copy: "jsfm_output"
                removeObject: wetCh[1]
            else
                selectObject: wetCh[1]
                outDur = Get total duration
                Create Sound from formula: "jsfm_output", numChannels, 0, outDur, originalSR, "0"
                finalOutput = selected("Sound")
                for ch from 1 to numChannels
                    selectObject: finalOutput
                    Formula (part): 0, outDur, ch, ch, "object[" + string$(wetCh[ch]) + ",1,col]"
                endfor
                for ch from 1 to numChannels
                    removeObject: wetCh[ch]
                endfor
            endif
            for ch from 1 to numChannels
                removeObject: dryCh[ch]
            endfor

            # Explicit output level policy.
            selectObject: finalOutput
            prePeak = Get absolute extremum: 0, 0, "None"
            if output_level_mode = 2
                if prePeak > ceiling_peak
                    Scale peak: ceiling_peak
                endif
            elsif output_level_mode = 3
                if prePeak > 0
                    Scale peak: ceiling_peak
                endif
            endif

            # Restore original time domain.
            selectObject: finalOutput
            Shift times by: originalXmin
            Rename: originalName$ + "_JitterShimmer_" + presetName$
            resultID = selected("Sound")
            resultSounds#[current] = resultID

            if keep_intermediates
                # Keep the useful analysis objects only.
                selectObject: pitch
                Rename: originalName$ + "_JS_pitch"
                if pointProcess <> 0
                    selectObject: pointProcess
                    Rename: originalName$ + "_JS_pulses"
                endif
                selectObject: formantObj
                Rename: originalName$ + "_JS_landmarks"
                removeObject: formantPath
            else
                if pointProcess <> 0
                    removeObject: pointProcess
                endif
                removeObject: pitch, formantPath, formantObj
            endif
            removeObject: analysisSound, workSound

            appendInfoLine: "Complete: ", selected$("Sound")
            if play_result
                selectObject: resultID
                Play
            endif
        endif
    endif
endfor

# ============================================================
# VISUALIZATION - first processed sound only
# ============================================================
if draw_visualization and numSounds > 0 and resultSounds#[1] <> 0
    appendInfoLine: "Drawing visualization..."
    selectObject: sounds#[1]
    vizOrigDur = Get total duration
    vizOrigXmin = Get start time
    vizOrigSR = Get sampling frequency
    vizEnd = min(vizOrigXmin + 5, vizOrigXmin + vizOrigDur)

    selectObject: sounds#[1]
    if vizOrigDur > 5
        originalViz = Extract part: vizOrigXmin, vizEnd, "rectangular", 1, "no"
    else
        originalViz = Copy: "jsfm_viz_orig"
    endif
    vizChannels = Get number of channels
    if vizChannels > 1
        Convert to mono
        tmpMono = selected("Sound")
        removeObject: originalViz
        originalViz = tmpMono
    endif

    selectObject: resultSounds#[1]
    if vizOrigDur > 5
        resultViz = Extract part: vizOrigXmin, vizEnd, "rectangular", 1, "no"
    else
        resultViz = Copy: "jsfm_viz_result"
    endif
    vizChannels = Get number of channels
    if vizChannels > 1
        Convert to mono
        tmpMono = selected("Sound")
        removeObject: resultViz
        resultViz = tmpMono
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "Jitter-Shimmer Formant Mapping v3.0"
    Font size: 7
    Colour: "{0.4,0.4,0.4}"
    Text: 0.5, "centre", 0.20, "half", presetName$ + " | spectral-envelope landmarks"

    maxVizFreq = min(5000, vizOrigSR / 2 - 50)

    Select outer viewport: 0, 4, 0.7, 2.6
    Select inner viewport: 0.55, 3.75, 0.85, 2.45
    selectObject: originalViz
    specO = To Spectrogram: 0.005, maxVizFreq, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, maxVizFreq, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Original"
    removeObject: specO

    Select outer viewport: 4, 8, 0.7, 2.6
    Select inner viewport: 4.35, 7.75, 0.85, 2.45
    selectObject: resultViz
    specR = To Spectrogram: 0.005, maxVizFreq, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, maxVizFreq, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Processed"
    removeObject: specR

    # Landmark map
    Select outer viewport: 0, 8, 2.8, 4.55
    Select inner viewport: 0.65, 7.7, 2.95, 4.4
    Axes: 0.5, 5.5, 0, maxVizFreq
    Paint rectangle: "{0.97,0.97,0.97}", 0.5, 5.5, 0, maxVizFreq
    for fn from 1 to 5
        if vizHaveLandmarks and vizOld_'fn' <> undefined
            Colour: "{0.55,0.55,0.55}"
            Draw line: fn, vizOld_'fn', fn, vizTarget_'fn'
            Paint circle: "{0.55,0.55,0.55}", fn, vizOld_'fn', 0.045
            Paint circle: "{0.20,0.55,0.80}", fn, vizTarget_'fn', 0.060
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Formant landmarks: grey = measured, blue = target"

    Select outer viewport: 0, 8, 4.7, 5.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text: 0.5, "centre", 0.68, "half", "Jitter " + fixed$(vizJitter, 3) + "% | Shimmer " + fixed$(vizShimmer, 3) + "% | F1-F2 x" + fixed$(vizLowShift, 3) + " | F3-F5 x" + fixed$(vizHighShift, 3)
    Text: 0.5, "centre", 0.30, "half", "Static FFT per channel | original phase preserved | confidence " + string$(vizConfidence)

    removeObject: originalViz, resultViz
endif

# Final selection: all results.
if numSounds > 0
    firstResult = 0
    for i from 1 to numSounds
        if resultSounds#[i] <> 0
            if firstResult = 0
                selectObject: resultSounds#[i]
                firstResult = 1
            else
                plusObject: resultSounds#[i]
            endif
        endif
    endfor
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="

# ============================================================
# PROCEDURES
# ============================================================
procedure spectralWarpChannel: .inputSound
    selectObject: .inputSound
    .dur = Get total duration
    .spec = To Spectrum: "yes"
    selectObject: .spec
    Formula: "self * 10^(min(" + shapeLimit$ + ",max(-" + shapeLimit$ + "," + expr$ + "))/20)"
    .full = To Sound
    removeObject: .spec
    selectObject: .full
    .out = Extract part: 0, .dur, "rectangular", 1, "no"
    removeObject: .full
    .result = .out
endproc

procedure extractNumber: .text$, .label$
    .index = index(.text$, .label$)
    if .index = 0
        .result = undefined
    else
        .length = length(.label$)
        .start = .index + .length
        .rest$ = mid$(.text$, .start, 50)
        .endPercent = index(.rest$, "%")
        .endSpace = index(.rest$, " ")
        .endNewline = index(.rest$, newline$)
        .end = 999
        if .endPercent > 0 and .endPercent < .end
            .end = .endPercent
        endif
        if .endSpace > 0 and .endSpace < .end
            .end = .endSpace
        endif
        if .endNewline > 0 and .endNewline < .end
            .end = .endNewline
        endif
        if .end = 999
            .end = length(.rest$) + 1
        endif
        .valStr$ = left$(.rest$, .end - 1)
        .valStr$ = replace$(.valStr$, "%", "", 0)
        .valStr$ = replace$(.valStr$, " ", "", 0)
        .result = number(.valStr$)
    endif
endproc
