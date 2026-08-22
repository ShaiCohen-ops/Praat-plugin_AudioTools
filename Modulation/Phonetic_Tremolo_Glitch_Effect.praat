# ============================================================
# Praat AudioTools - Phonetic_Tremolo_Glitch_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Acoustic-class tremolo/glitch processor. A mono analysis signal is
#   classified framewise into vowel-like, fricative-like, silence, and
#   other regions using Pitch, Intensity, Harmonicity, and structural
#   Formant/Bandwidth cues. This is an acoustic proxy, not phoneme or
#   speech recognition.
#
#   Vowel-like regions receive sinusoidal tremolo. Fricative-like regions
#   receive a causal delay glitch. Silence regions are attenuated/gated.
#   Classification is shared across all channels; processing preserves the
#   input channel count, sample rate, duration, and start time.
#
# Changelog v0.4:
#   - VISUALIZATION / FORM STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#   - Technical controls moved to optional Advanced settings;
#     defaults remain identical to the previous main form.
#
# v0.3 changes:
#   - Separates analysis/classification from processing and merges adjacent
#     frames of the same class into regions.
#   - Adds short dry crossfades at class boundaries to reduce clicks.
#   - Makes fricative shift causal (delay; reads past material, never future).
#   - Uses local sound time for tremolo phase, independent of Sound xmin.
#   - Removes hidden 1.5x fricative and 1.1x "other" gain boosts.
#   - Adds exact 0% Dry/Wet bypass, attenuation-only Safety_peak, and
#     user-visible Silence_gain.
#   - Adds an intensity-only fast path when only silence gating is active.
#   - Updates visualization to the AudioTools house text layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling_rate = Get sampling frequency
sound_xmin = Get start time
sound_xmax = Get end time
numChannels = Get number of channels

form Phonetic Tremolo/Glitch Effect v0.4
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Vocal Texture
        option Hard Robot Glitch
        option Broken Radio (High Speed)
        option Fricative Smear (Long Delay)
        option Deep Vowel Tremolo
        option Clean Gated (Silence Removal)

    comment --- Musical effect controls ---
    real Tremolo_rate_hz: 8.0
    real Tremolo_depth: 0.7
    real Fricative_delay_seconds: 0.015
    real Silence_gain: 0.05
    real Transition_ms: 2.0
    real Dry_wet_percent: 100

    boolean Advanced_settings: 0
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# Advanced defaults: identical to the previous main-form defaults.
frame_step_seconds = 0.01
max_formant_hz = 5500
vowel_hnr_threshold = 5.0
vowel_f1_min_hz = 300
fricative_hnr_max = 3.0
silence_intensity_threshold = 45
safety_peak = 0.99

if advanced_settings
    beginPause: "Phonetic Tremolo/Glitch Effect v0.4 - Advanced settings"
        comment: "=== Feature extraction ==="
        real: "Frame_step_seconds", "0.01"
        real: "Max_formant_hz", "5500"
        comment: "=== Classification thresholds ==="
        real: "Vowel_hnr_threshold", "5.0"
        real: "Vowel_f1_min_hz", "300"
        real: "Fricative_hnr_max", "3.0"
        real: "Silence_intensity_threshold", "45"
        comment: "=== Output safety ==="
        real: "Safety_peak", "0.99"
    clicked = endPause: "Continue", 1
endif

# ============================================================
# PRESETS
# ============================================================
presetName$ = preset$
if preset = 2
    tremolo_rate_hz = 4.0
    tremolo_depth = 0.3
    fricative_delay_seconds = 0.005
    silence_intensity_threshold = 40
    silence_gain = 0.10
elsif preset = 3
    tremolo_rate_hz = 12.0
    tremolo_depth = 0.9
    fricative_delay_seconds = 0.030
    silence_intensity_threshold = 50
    silence_gain = 0.02
elsif preset = 4
    tremolo_rate_hz = 25.0
    tremolo_depth = 0.8
    fricative_delay_seconds = 0.010
    silence_intensity_threshold = 45
    silence_gain = 0.03
elsif preset = 5
    tremolo_rate_hz = 6.0
    tremolo_depth = 0.2
    fricative_delay_seconds = 0.080
    fricative_hnr_max = 5.0
    silence_gain = 0.05
elsif preset = 6
    tremolo_rate_hz = 15.0
    tremolo_depth = 1.0
    fricative_delay_seconds = 0.0
    silence_gain = 0.05
elsif preset = 7
    tremolo_rate_hz = 0.0
    tremolo_depth = 0.0
    fricative_delay_seconds = 0.0
    silence_intensity_threshold = 60
    silence_gain = 0.0
endif

# ============================================================
# VALIDATION / METADATA
# ============================================================
if duration <= 0
    exitScript: "Error: Sound has zero duration."
endif
if duration < 0.05
    exitScript: "Error: Sound is too short for acoustic classification (need at least 50 ms)."
endif

frame_step_seconds = min(0.1, max(0.002, frame_step_seconds))
tremolo_rate_hz = max(0, tremolo_rate_hz)
tremolo_depth = min(1, max(0, tremolo_depth))
fricative_delay_seconds = min(duration, max(0, fricative_delay_seconds))
silence_gain = min(1, max(0, silence_gain))
transition_ms = min(50, max(0, transition_ms))
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))

nyquist = sampling_rate / 2
safeMaxFormant = min(max_formant_hz, nyquist - 50)
if safeMaxFormant < 1200 and dry_wet_percent > 0 and (tremolo_depth > 0 or fricative_delay_seconds > 0 or draw_visualization)
    exitScript: "Error: Sample rate is too low for the requested formant-based classification."
endif

appendInfoLine: "=== Phonetic Tremolo/Glitch Effect v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sampling_rate, 0), " Hz"
appendInfoLine: "Classifier: acoustic proxy (vowel-like / fricative-like / silence / other)"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"

# ============================================================
# EXACT BYPASS FAST PATH
# ============================================================
if dry_wet_percent <= 0
    selectObject: original
    result = Copy: original_name$ + "_phonetic_bypass"
    numFrames = max(1, ceiling(duration / frame_step_seconds))
    classFrames# = zero#(numFrames)
    for i from 1 to numFrames
        classFrames#[i] = 4
    endfor
    vowelCount = 0
    fricativeCount = 0
    silenceCount = 0
    otherCount = numFrames
    formantValidCount = 0
    formantRejectedCount = 0
    analysisSource$ = "bypassed"
    fullAnalysis = 0
else
    # ========================================================
    # ANALYSIS SOURCE
    # ========================================================
    if numChannels = 1
        selectObject: original
        Copy: original_name$ + "_analysis"
        analysisSound = selected("Sound")
        analysisSource$ = "mono input"
    else
        selectObject: original
        Convert to mono
        analysisSound = selected("Sound")
        Rename: original_name$ + "_analysis_fold"
        monoPeak = Get absolute extremum: 0, 0, "None"

        bestChannel = 1
        bestPeak = -1
        for ch from 1 to numChannels
            selectObject: original
            Extract one channel: ch
            chTmp = selected("Sound")
            chPeak = Get absolute extremum: 0, 0, "None"
            if chPeak > bestPeak
                bestPeak = chPeak
                bestChannel = ch
            endif
            removeObject: chTmp
        endfor

        if bestPeak > 0 and monoPeak < 0.10 * bestPeak
            removeObject: analysisSound
            selectObject: original
            Extract one channel: bestChannel
            analysisSound = selected("Sound")
            Rename: original_name$ + "_analysis_ch" + string$(bestChannel)
            analysisSource$ = "channel " + string$(bestChannel) + " (fold-down cancellation fallback)"
        else
            analysisSource$ = "mono fold-down"
        endif
    endif

    # Intensity is always needed because silence is an effect class.
    selectObject: analysisSound
    To Intensity: 75, 0, "yes"
    intensity_id = selected("Intensity")

    # If tremolo and fricative delay are both disabled, non-silent class
    # distinctions do not affect the sound. Skip Pitch/HNR/Formant unless
    # visualization explicitly asks for the detailed classes.
    fullAnalysis = 0
    if tremolo_depth > 0 or fricative_delay_seconds > 0 or draw_visualization
        fullAnalysis = 1
    endif

    if fullAnalysis
        selectObject: analysisSound
        To Pitch: frame_step_seconds, 75, min(600, nyquist - 50)
        pitch_id = selected("Pitch")

        selectObject: analysisSound
        To Formant (burg): frame_step_seconds, 5, safeMaxFormant, 0.025, 50
        formant_id = selected("Formant")

        selectObject: analysisSound
        To Harmonicity (cc): frame_step_seconds, 75, 0.1, 1.0
        hnr_id = selected("Harmonicity")
    endif

    # ========================================================
    # CLASSIFY FRAMES FIRST
    # ========================================================
    numFrames = max(1, ceiling(duration / frame_step_seconds))
    classFrames# = zero#(numFrames)
    midTimes# = zero#(numFrames)

    vowelCount = 0
    fricativeCount = 0
    silenceCount = 0
    otherCount = 0
    formantValidCount = 0
    formantRejectedCount = 0

    for i from 1 to numFrames
        t_start = sound_xmin + (i - 1) * frame_step_seconds
        t_end = min(sound_xmin + i * frame_step_seconds, sound_xmax)
        t_mid = 0.5 * (t_start + t_end)
        midTimes#[i] = t_mid

        selectObject: intensity_id
        int_val = Get value at time: t_mid, "cubic"
        if int_val = undefined
            int_val = -300
        endif

        if int_val < silence_intensity_threshold
            classNum = 3
            silenceCount = silenceCount + 1
        elsif fullAnalysis = 0
            classNum = 4
            otherCount = otherCount + 1
        else
            selectObject: pitch_id
            f0_val = Get value at time: t_mid, "Hertz", "Linear"
            if f0_val = undefined
                f0_val = 0
            endif

            selectObject: hnr_id
            hnr_val = Get value at time: t_mid, "cubic"
            if hnr_val = undefined
                hnr_val = -100
            endif

            selectObject: formant_id
            f1_val = Get value at time: 1, t_mid, "Hertz", "Linear"
            f2_val = Get value at time: 2, t_mid, "Hertz", "Linear"
            f3_val = Get value at time: 3, t_mid, "Hertz", "Linear"
            bw1_val = Get bandwidth at time: 1, t_mid, "Hertz", "Linear"
            bw2_val = Get bandwidth at time: 2, t_mid, "Hertz", "Linear"
            bw3_val = Get bandwidth at time: 3, t_mid, "Hertz", "Linear"

            formantValid = 0
            if f1_val <> undefined and f2_val <> undefined and f3_val <> undefined and bw1_val <> undefined and bw2_val <> undefined and bw3_val <> undefined
                gap12 = f2_val - f1_val
                gap23 = f3_val - f2_val
                span13 = f3_val - f1_val
                minSpan = 450
                if f0_val > 0
                    minSpan = max(minSpan, 1.25 * f0_val)
                endif
                bandwidthOK = 0
                if bw1_val > 0 and bw2_val > 0 and bw3_val > 0 and bw1_val < min(1000, 0.90 * f1_val) and bw2_val < min(1200, 0.70 * f2_val) and bw3_val < min(1500, 0.60 * f3_val)
                    bandwidthOK = 1
                endif
                if f1_val > vowel_f1_min_hz and f2_val > f1_val and f3_val > f2_val and gap12 >= 120 and gap23 >= 180 and span13 >= minSpan and f3_val < safeMaxFormant and bandwidthOK = 1
                    formantValid = 1
                endif
            endif

            if formantValid
                formantValidCount = formantValidCount + 1
            else
                formantRejectedCount = formantRejectedCount + 1
            endif

            if hnr_val > vowel_hnr_threshold and f0_val > 0 and formantValid = 1
                classNum = 1
                vowelCount = vowelCount + 1
            elsif hnr_val < fricative_hnr_max and f0_val = 0
                classNum = 2
                fricativeCount = fricativeCount + 1
            else
                classNum = 4
                otherCount = otherCount + 1
            endif
        endif
        classFrames#[i] = classNum
    endfor

    # ========================================================
    # PROCESS MERGED CLASS REGIONS
    # ========================================================
    refName$ = "PTGref" + string$(original)
    selectObject: original
    Copy: refName$
    refSound = selected("Sound")

    selectObject: original
    Copy: original_name$ + "_phonetic_" + presetName$
    output_id = selected("Sound")

    globalWet = dry_wet_percent / 100
    transitionSecUser = transition_ms / 1000

    regionStartFrame = 1
    while regionStartFrame <= numFrames
        regionClass = classFrames#[regionStartFrame]
        regionEndFrame = regionStartFrame
        while regionEndFrame < numFrames and classFrames#[regionEndFrame + 1] = regionClass
            regionEndFrame = regionEndFrame + 1
        endwhile

        regionStart = sound_xmin + (regionStartFrame - 1) * frame_step_seconds
        regionEnd = min(sound_xmax, sound_xmin + regionEndFrame * frame_step_seconds)
        regionDur = max(0, regionEnd - regionStart)
        fadeSec = min(transitionSecUser, 0.5 * regionDur)

        # Edge crossfade coefficient e(x): 0 at region edges, 1 in the body.
        # Each effect is blended against the untouched reference Sound.
        if regionClass = 1 and tremolo_depth > 0 and tremolo_rate_hz > 0
            selectObject: output_id
            Formula (part): regionStart, regionEnd, 1, numChannels,
                ... ~ Sound_'refName$'(x) * (1 - globalWet * (if fadeSec <= 0 then 1 else if x < regionStart + fadeSec then max(0,min(1,(x-regionStart)/fadeSec)) else if x > regionEnd - fadeSec then max(0,min(1,(regionEnd-x)/fadeSec)) else 1 fi fi fi) * tremolo_depth * (0.5 * (1 + sin(2*pi*tremolo_rate_hz*(x-sound_xmin)))))
        elsif regionClass = 2 and fricative_delay_seconds > 0
            selectObject: output_id
            Formula (part): regionStart, regionEnd, 1, numChannels,
                ... ~ Sound_'refName$'(x) * (1 - globalWet * (if fadeSec <= 0 then 1 else if x < regionStart + fadeSec then max(0,min(1,(x-regionStart)/fadeSec)) else if x > regionEnd - fadeSec then max(0,min(1,(regionEnd-x)/fadeSec)) else 1 fi fi fi)) + Sound_'refName$'(x-fricative_delay_seconds) * globalWet * (if fadeSec <= 0 then 1 else if x < regionStart + fadeSec then max(0,min(1,(x-regionStart)/fadeSec)) else if x > regionEnd - fadeSec then max(0,min(1,(regionEnd-x)/fadeSec)) else 1 fi fi fi)
        elsif regionClass = 3 and silence_gain < 1
            selectObject: output_id
            Formula (part): regionStart, regionEnd, 1, numChannels,
                ... ~ Sound_'refName$'(x) * (1 - globalWet * (if fadeSec <= 0 then 1 else if x < regionStart + fadeSec then max(0,min(1,(x-regionStart)/fadeSec)) else if x > regionEnd - fadeSec then max(0,min(1,(regionEnd-x)/fadeSec)) else 1 fi fi fi) * (1-silence_gain))
        endif

        regionStartFrame = regionEndFrame + 1
    endwhile

    result = output_id

    # Cleanup analysis/reference objects.
    removeObject: intensity_id, analysisSound, refSound
    if fullAnalysis
        removeObject: pitch_id, formant_id, hnr_id
    endif
endif

# ============================================================
# SAFETY / INFO
# ============================================================
selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if dry_wet_percent > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Analysis source: ", analysisSource$
if dry_wet_percent > 0
    if fullAnalysis
        appendInfoLine: "Analysis: Pitch + Intensity + Harmonicity + Formant structure"
    else
        appendInfoLine: "Analysis: intensity-only fast path"
    endif
endif
appendInfoLine: "Classification: vowel-like ", vowelCount, " | fricative-like ", fricativeCount, " | silence ", silenceCount, " | other ", otherCount
if fullAnalysis
    appendInfoLine: "Formant-valid frames: ", formantValidCount, "/", numFrames
endif
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(finalPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
else
    appendInfoLine: "Safety: disabled"
endif
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
if draw_visualization
    pageHeight = 5.7
    maxVizFrames = min(numFrames, 500)

    Erase all
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Phonetic Tremolo/Glitch v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", original_name$ + "  |  " + presetName$ + "  |  acoustic-class proxy"

    # ---- INPUT ----
    Select outer viewport: 0, 4.2, 0.75, 2.25
    Select inner viewport: 0.55, 4.00, 0.95, 2.13
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT ----
    Select outer viewport: 4.2, 8, 0.75, 2.25
    Select inner viewport: 4.55, 7.75, 0.95, 2.13
    selectObject: result
    Colour: "{0.25, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- CLASS TIMELINE ----
    Select outer viewport: 0, 8, 2.35, 3.65
    Select inner viewport: 0.55, 7.75, 2.53, 3.53
    Axes: sound_xmin, sound_xmax, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", sound_xmin, sound_xmax, 0, 1

    for v from 1 to maxVizFrames
        srcIdx = floor((v - 1) / maxVizFrames * numFrames) + 1
        srcIdx = min(numFrames, max(1, srcIdx))
        classVal = classFrames#[srcIdx]
        leftT = sound_xmin + (srcIdx - 1) * frame_step_seconds
        rightT = min(sound_xmax, leftT + frame_step_seconds)
        if classVal = 1
            Paint rectangle: "{0.60, 0.45, 0.75}", leftT, rightT, 0, 1
        elsif classVal = 2
            Paint rectangle: "{0.35, 0.50, 0.80}", leftT, rightT, 0, 1
        elsif classVal = 3
            Paint rectangle: "{0.72, 0.72, 0.72}", leftT, rightT, 0, 1
        else
            Paint rectangle: "{0.72, 0.76, 0.84}", leftT, rightT, 0, 1
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Acoustic-class timeline"
    Font size: 6
    Text bottom: "yes", "Time (s)"

    # ---- LEGEND + COUNTS ----
    Select outer viewport: 0, 8, 3.75, 4.45
    Select inner viewport: 0.55, 7.75, 3.83, 4.37
    Axes: 0, 8, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 8, 0, 1
    Paint rectangle: "{0.60, 0.45, 0.75}", 0.2, 0.55, 0.30, 0.70
    Paint rectangle: "{0.35, 0.50, 0.80}", 2.15, 2.50, 0.30, 0.70
    Paint rectangle: "{0.72, 0.72, 0.72}", 4.10, 4.45, 0.30, 0.70
    Paint rectangle: "{0.72, 0.76, 0.84}", 5.95, 6.30, 0.30, 0.70
    Colour: "Black"
    Font size: 6
    Text: 0.70, "left", 0.50, "half", "Vowel-like: " + string$(vowelCount)
    Text: 2.65, "left", 0.50, "half", "Fricative-like: " + string$(fricativeCount)
    Text: 4.60, "left", 0.50, "half", "Silence: " + string$(silenceCount)
    Text: 6.45, "left", 0.50, "half", "Other: " + string$(otherCount)
    Draw inner box

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, 4.55, 5.45
    Select inner viewport: 0.55, 7.75, 4.62, 5.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half", "Tremolo: " + fixed$(tremolo_rate_hz, 1) + " Hz @ " + fixed$(100*tremolo_depth, 0) + "%  |  fricative delay: " + fixed$(1000*fricative_delay_seconds, 1) + " ms  |  silence gain: " + fixed$(silence_gain, 2) + "  |  transition: " + fixed$(transition_ms, 1) + " ms"
    Text: 0.02, "left", 0.20, "half", "Wet: " + fixed$(dry_wet_percent, 0) + "%  |  silence < " + fixed$(silence_intensity_threshold, 0) + " dB  |  analysis: " + analysisSource$ + "  |  " + fixed$(duration, 2) + " s / " + fixed$(sampling_rate, 0) + " Hz / " + string$(numChannels) + " ch"

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

selectObject: result
if play_result
    Play
endif
selectObject: result
