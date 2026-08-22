# ============================================================
# Praat AudioTools - Ligeti_Micropolyphonic_Choir_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 (2026)
# v1.3.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ligeti Micropolyphonic Choir Machine - dense, slowly-evolving
#   textures via N pitch-detuned, time-offset, fade-enveloped voices
#   summed into a single output buffer.
#
# Changelog v1.2 (2026):
#   - Public form/defaults, preset identities, output naming and final
#     selection are unchanged.
#   - Fixed Time_offset_range_s semantics: both flat and Gaussian modes now
#     use the advertised +/-time_range support. v1.1 flat mode accidentally
#     used only +/-time_range/2.
#   - Stereo-spread wet synthesis now uses one explicit mono choir source;
#     non-spread multichannel mode preserves corresponding source channels.
#   - Cross-object Formula reads now specify row+col explicitly.
#   - 3+ channel dry padding uses the dry object's actual channel count,
#     avoiding Concatenate channel-count failures.
#   - Custom Number_of_voices is rounded to an integer >=2; duration variation
#     is clamped below 1 so dur_factor cannot become zero/negative.
#   - Attack/release fade is capped at half the rendered voice length to avoid
#     overlapping/pathological envelopes on very short voices.
#   - Working downsample/mono intermediates are cleaned consistently.
#   - Normalize_output is silence-safe; normalization behavior is otherwise
#     unchanged.
#
# Changelog v1.1 (2026):
#   Speed-focused refactor. Output is mathematically equivalent to
#   v1.0 (same RNG sequence, same mixing) — just considerably faster.
#
#   - SPEED: Combined pitch-shift and time-stretch into a single
#     resample per voice (was: two). Both operations are
#     SR-override + resample, so they commute as multiplicative
#     factors and can be applied in one pass.
#   - SPEED: Resample-precision parameter is now tied to speed_mode:
#       Full Quality   -> precision 50 (original)
#       Balanced       -> precision 10
#       Fast           -> precision  5
#     For dense choir textures with small pitch deviations, the
#     aliasing from lower precision is masked by the texture itself.
#   - SPEED: Folded envelope (attack/release fade) and per-voice
#     gain into the final mix Formula. Eliminates two full-buffer
#     passes per voice. Envelope math is computed in sample units
#     (no division-by-sample-rate per sample inside Formula).
#   - SPEED: When both pitch and time-stretch round to negligible,
#     skip the resample entirely.
# ============================================================

form Ligeti Micropolyphonic Choir v1.3.1
    comment === Behavioral Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Static Spectral Fog (Gaussian Mass)
        option Fracturing Mass (Gradual Detuning)
        option Stereo Torsion (L=Pure, R=Detuned)
        option Bimodal Web (High/Low Split)
        option Breathing Field (Uniform Cloud)
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    
    comment === Voice Parameters ===
    positive Number_of_voices 60
    positive Time_offset_range_s 0.8
    positive Duration_variation 0.05
    positive Max_pitch_cents 15.0
    
    comment === Output ===
    boolean Stereo_spread 1
    positive Attack_fade_ms 30
    positive Voice_gain 1.0
    
    comment === Mix ===
    real Wet_dry_percent 80
    comment (0 = dry only, 100 = wet only)
    
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Check Input
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sampleRate = Get sampling frequency
originalChannels = Get number of channels

# Setup Defaults
structure$ = "uniform"
dist_shape$ = "flat"
time_range = 0.5
pitch_max = 15
dur_var = 0.05
n_voices = 50
gain = 1.0
fade = 25
use_stereo = stereo_spread

# Apply Presets
if preset = 2
    structure$ = "uniform"
    dist_shape$ = "gaussian"
    n_voices = 60
    time_range = 0.5
    pitch_max = 8
    dur_var = 0.02
    gain = 0.8
    fade = 50
    presetName$ = "Fog"
elsif preset = 3
    structure$ = "arc_fracture"
    dist_shape$ = "flat"
    n_voices = 60
    time_range = 1.0
    pitch_max = 35
    dur_var = 0.08
    gain = 0.7
    fade = 30
    presetName$ = "Fracture"
elsif preset = 4
    structure$ = "asymmetry"
    dist_shape$ = "flat"
    n_voices = 50
    time_range = 0.6
    pitch_max = 25
    dur_var = 0.05
    gain = 0.9
    fade = 20
    use_stereo = 1
    presetName$ = "Torsion"
elsif preset = 5
    structure$ = "bimodal"
    dist_shape$ = "flat"
    n_voices = 40
    time_range = 0.8
    pitch_max = 20
    dur_var = 0.1
    gain = 0.85
    fade = 15
    presetName$ = "Bimodal"
elsif preset = 6
    structure$ = "uniform"
    dist_shape$ = "flat"
    n_voices = 40
    time_range = 1.2
    pitch_max = 12
    dur_var = 0.08
    gain = 0.8
    fade = 40
    presetName$ = "Breathing"
else
    n_voices = number_of_voices
    time_range = time_offset_range_s
    pitch_max = max_pitch_cents
    dur_var = duration_variation
    gain = voice_gain
    fade = attack_fade_ms
    presetName$ = "Custom"
endif

# Internal guards for Custom/caller-supplied values.
n_voices = round(n_voices)
if n_voices < 2
    n_voices = 2
endif
if time_range < 0
    time_range = 0
endif
if pitch_max < 0
    pitch_max = abs(pitch_max)
endif
if dur_var < 0
    dur_var = 0
endif
if dur_var >= 1
    dur_var = 0.95
endif
if gain < 0
    gain = 0
endif
if fade < 0
    fade = 0
endif

# Set target sample rate and resample precision per speed mode.
# v1.1: precision is now mode-dependent. Quality 50 is Praat's
# default for high-quality work; 10 is fine for dense textures
# with small detuning; 5 is fast and audibly fine when the source
# is being multiplied 60× into a polyphonic mass.
if speed_mode = 1
    targetSR = 0
    resamplePrecision = 50
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    resamplePrecision = 10
    speedStr$ = "Balanced"
else
    targetSR = 11025
    resamplePrecision = 5
    speedStr$ = "Fast"
endif

# Clamp wet/dry
wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Output channels
if use_stereo = 1
    outChannels = 2
else
    outChannels = originalChannels
endif

startTime = stopwatch

# Info
writeInfoLine: "=== Ligeti Micropolyphonic Choir v1.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: ""
appendInfoLine: "Structure: ", structure$
appendInfoLine: "Distribution: ", dist_shape$
appendInfoLine: "Voices: ", n_voices
appendInfoLine: "Time range: ±", fixed$(time_range, 2), " s"
appendInfoLine: "Pitch range: ±", pitch_max, " cents"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# === OPTIONAL DOWNSAMPLING / CHOIR SOURCE PREP ===
workingSound = original
workingIsTemporary = 0
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: original
    Resample: targetSR, 50
    workingSound = selected("Sound")
    workingIsTemporary = 1
    workingSR = targetSR
else
    workingSR = sampleRate
endif

# A panned choir is conceptually a set of mono voices positioned in stereo.
# Convert once here instead of implicitly reading channel 1 from every voice.
selectObject: workingSound
workingChannels = Get number of channels
if use_stereo = 1 and workingChannels > 1
    Convert to mono
    monoWork = selected("Sound")
    if workingIsTemporary = 1
        removeObject: workingSound
    endif
    workingSound = monoWork
    workingIsTemporary = 1
    workingChannels = 1
endif

# Store voice data for visualization
for v from 1 to n_voices
    voicePitch[v] = 0
    voiceOffset[v] = 0
    voicePan[v] = 0
endfor

# Create Output Buffer
selectObject: workingSound
workingDur = Get total duration
output_dur = workingDur + time_range + 0.5

Create Sound from formula: "choir_output", outChannels, 0, output_dur, workingSR, "0"
output = selected("Sound")

# ============================================================
# VOICE GENERATION LOOP (optimized: no padding, no per-voice stereo)
# ============================================================

appendInfoLine: "Generating ", n_voices, " voices..."

for voice from 1 to n_voices
    
    if voice mod 10 = 0
        appendInfoLine: "  Voice ", voice, " / ", n_voices
    endif
    
    selectObject: workingSound
    Copy: "voice_temp"
    voiceCopy = selected("Sound")
    
    # Reset start time
    t_start = Get start time
    if t_start <> 0
        Shift times by: -t_start
    endif
    
    # === 1. CALCULATE PANNING ===
    pan_pos = randomUniform(-1, 1)
    voicePan[voice] = pan_pos
    
    # === 2. CALCULATE PITCH DEVIATION ===
    current_pitch_cents = 0
    
    if structure$ = "uniform"
        if pitch_max <= 0
            current_pitch_cents = 0
        elsif dist_shape$ = "gaussian"
            r1 = randomUniform(-1, 1)
            r2 = randomUniform(-1, 1)
            current_pitch_cents = ((r1 + r2) / 2) * pitch_max
        else
            current_pitch_cents = randomUniform(-pitch_max, pitch_max)
        endif
    elsif structure$ = "arc_fracture"
        intensity = voice / n_voices
        current_range = pitch_max * intensity
        current_pitch_cents = randomUniform(-current_range, current_range)
    elsif structure$ = "asymmetry"
        tension = (pan_pos + 1) / 2
        current_range = pitch_max * tension
        current_pitch_cents = randomUniform(-current_range, current_range)
    elsif structure$ = "bimodal"
        if voice mod 2 = 0
            current_pitch_cents = randomUniform(5, pitch_max)
        else
            current_pitch_cents = randomUniform(-pitch_max, -5)
        endif
    endif
    
    voicePitch[voice] = current_pitch_cents

    # === 3 + 4. COMBINED PITCH SHIFT + TIME STRETCH ===
    # v1.1: both operations are SR-override + resample, so they
    # commute as multiplicative factors on the override SR.
    # combined_factor = pitch_ratio / dur_factor.
    # When this rounds to ~1, the resample is skipped entirely.
    pitch_ratio = 2 ^ (current_pitch_cents / 1200)

    if dur_var <= 0
        dur_factor = 1
    elsif dist_shape$ = "gaussian"
        raw_rand = (randomUniform(-1, 1) + randomUniform(-1, 1)) / 2
        dur_factor = 1 + (raw_rand * dur_var)
    else
        dur_factor = 1 + randomUniform(-dur_var, dur_var)
    endif

    combined_factor = pitch_ratio / dur_factor

    if abs(combined_factor - 1) > 0.0008
        selectObject: voiceCopy
        new_sr_combined = workingSR * combined_factor
        Override sampling frequency: new_sr_combined
        Resample: workingSR, resamplePrecision
        temp = selected("Sound")
        removeObject: voiceCopy
        voiceCopy = temp

        # If the combined operation lengthened the voice past the
        # working duration window, trim. (When dur_factor > 1 and
        # pitch_ratio < 1 — voice is both lower and longer.)
        selectObject: voiceCopy
        s_dur = Get total duration
        if s_dur > workingDur + 0.01
            Extract part: 0, workingDur, "rectangular", 1, "no"
            temp = selected("Sound")
            removeObject: voiceCopy
            voiceCopy = temp
        endif
    endif

    # === 5 + 6. ENVELOPE + GAIN ===
    # v1.1: envelope and gain are no longer applied via separate
    # full-buffer Formulas. They are folded into the mix Formula
    # below, saving two passes over the voice buffer per voice.
    # We just compute the constants here.
    gain_per_voice = gain / sqrt(n_voices)
    fade_sec = fade / 1000
    fade_samples = round(fade_sec * workingSR)
    if fade_samples < 1
        fade_samples = 1
    endif
    
    # === 7. TIME OFFSET ===
    if time_range <= 0
        offset = 0
    elsif dist_shape$ = "gaussian"
        r1 = randomUniform(-0.5, 0.5)
        r2 = randomUniform(-0.5, 0.5)
        offset = (r1 + r2) * time_range
    else
        offset = randomUniform(-time_range, time_range)
    endif
    
    voiceOffset[voice] = offset
    
    # For negative offset: trim voice start
    if offset < 0
        cut_dur = abs(offset)
        selectObject: voiceCopy
        curr_dur = Get total duration
        if cut_dur < curr_dur
            Extract part: cut_dur, curr_dur, "rectangular", 1, "no"
            v_cut = selected("Sound")
            removeObject: voiceCopy
            voiceCopy = v_cut
        endif
        voiceMixStart = 0
    else
        voiceMixStart = offset
    endif
    
    # === 8. MIX INTO OUTPUT (folded envelope + gain + mix) ===
    # v1.1: envelope and gain are folded into this Formula instead
    # of running two prior full-buffer passes. This saves 2N voice-
    # buffer scans across N voices.
    #
    # Envelope (in sample units, voice-local index vCol = col - sOff):
    #   vCol < fade_samples            -> ramp in:  vCol / fade_samples
    #   voiceNs - vCol + 1 < fade_samples -> ramp out: (voiceNs - vCol + 1) / fade_samples
    #   else                           -> 1.0
    # When fade = 0, the envelope multiplier is constant 1 and we
    # build a simpler formula.
    selectObject: voiceCopy
    voiceNs = Get number of samples

    # A symmetric attack/release should not overlap on short rendered voices.
    if fade > 0 and voiceNs > 1
        maxFadeSamples = floor(voiceNs / 2)
        if fade_samples > maxFadeSamples
            fade_samples = maxFadeSamples
        endif
        if fade_samples < 1
            fade_samples = 1
        endif
    endif

    selectObject: output
    s1 = Get sample number from time: voiceMixStart
    if s1 < 1
        s1 = 1
    endif
    s2 = s1 + voiceNs - 1
    outNs = Get number of samples
    if s2 > outNs
        s2 = outNs
    endif
    sOff = s1 - 1

    voiceEnd_t = voiceMixStart + voiceNs / workingSR
    if voiceEnd_t > output_dur
        voiceEnd_t = output_dur
    endif

    voiceIdStr$ = string$(voiceCopy)
    sOffStr$ = string$(sOff)
    gainStr$ = string$(gain_per_voice)
    voiceNsStr$ = string$(voiceNs)
    fadeNsStr$ = string$(fade_samples)

    # Build the envelope/gain suffix once; channel routing is explicit below.
    if fade > 0
        vSuffix$ = " * (if (col - " + sOffStr$ + ") < " + fadeNsStr$
            ... + " then (col - " + sOffStr$ + ") / " + fadeNsStr$
            ... + " else if (" + voiceNsStr$ + " - (col - " + sOffStr$
            ... + ") + 1) < " + fadeNsStr$
            ... + " then (" + voiceNsStr$ + " - (col - " + sOffStr$
            ... + ") + 1) / " + fadeNsStr$
            ... + " else 1 fi fi)"
            ... + " * " + gainStr$
    else
        vSuffix$ = " * " + gainStr$
    endif

    if use_stereo = 1
        # workingSound/voiceCopy is explicitly mono in stereo-spread mode.
        vRead$ = "object[" + voiceIdStr$ + ", 1, col - " + sOffStr$ + "]" + vSuffix$
        l_gain = sqrt((1 - pan_pos) / 2)
        r_gain = sqrt((1 + pan_pos) / 2)
        selectObject: output
        Formula (part): voiceMixStart, voiceEnd_t, 1, 1,
            ... "self + " + vRead$ + " * " + string$(l_gain)
        Formula (part): voiceMixStart, voiceEnd_t, 2, 2,
            ... "self + " + vRead$ + " * " + string$(r_gain)
    elsif outChannels > 1
        # Preserve corresponding source channels when stereo spreading is off.
        selectObject: output
        for ch from 1 to outChannels
            vRead$ = "object[" + voiceIdStr$ + ", " + string$(ch) + ", col - " + sOffStr$ + "]" + vSuffix$
            Formula (part): voiceMixStart, voiceEnd_t, ch, ch,
                ... "self + " + vRead$
        endfor
    else
        vRead$ = "object[" + voiceIdStr$ + ", 1, col - " + sOffStr$ + "]" + vSuffix$
        selectObject: output
        Formula (part): voiceMixStart, voiceEnd_t, 1, 1,
            ... "self + " + vRead$
    endif

    removeObject: voiceCopy

endfor

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: ""
    appendInfoLine: "Upsampling to ", sampleRate, " Hz..."
    selectObject: output
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: output
    output = upsampledID
    
endif

# workingSound is no longer needed after all voice copies have been rendered.
if workingIsTemporary = 1
    removeObject: workingSound
endif

# Apply Wet/Dry Mix
if dry_level > 0
    selectObject: original
    Copy: "dry_extended"
    dryExt = selected("Sound")
    
    # Convert to stereo if needed
    if outChannels = 2 and originalChannels = 1
        Copy: "dry_R"
        dryR = selected("Sound")
        selectObject: dryExt, dryR
        Combine to stereo
        temp = selected("Sound")
        removeObject: dryExt, dryR
        dryExt = temp
    endif
    
    # Pad to output length
    selectObject: output
    finalOutputDur = Get total duration
    
    selectObject: dryExt
    curr_dur = Get total duration
    dryChannels = Get number of channels
    if curr_dur < finalOutputDur
        Create Sound from formula: "sil_dry", dryChannels, 0, finalOutputDur - curr_dur, sampleRate, "0"
        sil_dry = selected("Sound")
        selectObject: dryExt, sil_dry
        Concatenate
        temp = selected("Sound")
        removeObject: sil_dry, dryExt
        dryExt = temp
    endif
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dryExt)
    
    selectObject: output
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$
    
    removeObject: dryExt
endif

# Normalize (same requested behavior, but silence-safe)
selectObject: output
if normalize_output = 1
    outputPeak = Get absolute extremum: 0, 0, "None"
    if outputPeak > 0
        Scale peak: 0.95
    endif
endif

Rename: originalName$ + "_ligeti_" + presetName$
result = selected("Sound")

processingTime = stopwatch - startTime

# VISUALIZATION
if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.62
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Ligeti Micropolyphonic Choir##" + " | v1.3.1"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + string$(n_voices) + " voices"
        ... + "  |  ±" + fixed$(pitch_max, 0) + " cents"
        ... + "  |  " + speedStr$
        ... + "  |  " + fixed$(processingTime, 1) + "s"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.60, 7.70, 0.57, 1.27
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.57, 1.27
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Input"
    Select inner viewport: 0.60, 7.70, 0.57, 1.27
    Axes: 0, 1, 0, 1
    Text top: "no", "Source: " + originalName$

    # ----------------------------------------------------------
    # Output waveform (L blue, R orange)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.60, 7.70, 1.41, 2.11
    selectObject: result
    nChResult = Get number of channels
    if nChResult > 1
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, originalDur, 0, 0, "no", "Curve"
        selectObject: result
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, originalDur, 0, 0, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: result
        Colour: "{0.55, 0.45, 0.68}"
        Draw: 0, originalDur, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.41, 2.11
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Choir"
    Select inner viewport: 0.60, 7.70, 1.41, 2.11
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Output spectrogram (shows the dense micropolyphonic mass)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.22, 3.42
    Select inner viewport: 0.60, 7.70, 2.28, 3.36
    selectObject: result
    if nChResult > 1
        Extract one channel: 1
        vizSpec = selected("Sound")
    else
        Copy: "vizSpec"
        vizSpec = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, originalDur, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, vizSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 2.28, 3.36
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Hz"
    Select inner viewport: 0.60, 7.70, 2.28, 3.36
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Choir spectrogram  (micropolyphonic texture)"

    # ----------------------------------------------------------
    # Voice scatter: Pitch vs Time Offset (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 3.50, 4.90
    Select inner viewport: 0.60, 3.85, 3.58, 4.82

    Axes: -time_range, time_range, -pitch_max * 1.2, pitch_max * 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -time_range, time_range, -pitch_max * 1.2, pitch_max * 1.2

    for v from 1 to n_voices
        vR = 0.50 + voicePan[v] * 0.30
        vG = 0.50
        vB = 0.50 - voicePan[v] * 0.30
        Paint circle: "{" + fixed$(vR, 2) + ", " + fixed$(vG, 2) + ", " + fixed$(vB, 2) + "}",
            ... voiceOffset[v], voicePitch[v], time_range * 0.025
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, -pitch_max * 1.2, 0, pitch_max * 1.2
    Draw line: -time_range, 0, time_range, 0
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 3.58, 4.82
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Pitch (cents)"
    Select inner viewport: 0.60, 3.85, 3.58, 4.82
    Axes: -time_range, time_range, -pitch_max * 1.2, pitch_max * 1.2
    Text bottom: "yes", "Time offset (s)"
    Text top: "no", "Voice cloud  (colour = pan)"

    # ----------------------------------------------------------
    # Voice scatter: Pan vs Pitch (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 3.50, 4.90
    Select inner viewport: 4.45, 7.70, 3.58, 4.82

    Axes: -1.2, 1.2, -pitch_max * 1.2, pitch_max * 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -pitch_max * 1.2, pitch_max * 1.2

    for v from 1 to n_voices
        vR = 0.50 + voicePan[v] * 0.30
        vG = 0.50
        vB = 0.50 - voicePan[v] * 0.30
        Paint circle: "{" + fixed$(vR, 2) + ", " + fixed$(vG, 2) + ", " + fixed$(vB, 2) + "}",
            ... voicePan[v], voicePitch[v], 0.04
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, -pitch_max * 1.2, 0, pitch_max * 1.2
    Draw line: -1.2, 0, 1.2, 0
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 3.58, 4.82
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Pitch (cents)"
    Select inner viewport: 4.45, 7.70, 3.58, 4.82
    Axes: -1.2, 1.2, -pitch_max * 1.2, pitch_max * 1.2
    Text bottom: "yes", "Pan (L ← → R)"
    Text top: "no", "Stereo field"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.05, 6.05
    Select inner viewport: 0.60, 7.70, 5.12, 5.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", 
        ... "Preset: " + presetName$
        ... + "  |  Structure: " + structure$
        ... + "  |  Voices: " + string$(n_voices)
        ... + "  |  Pitch: ±" + fixed$(pitch_max, 0) + " ct"
        ... + "  |  Time: ±" + fixed$(time_range, 2) + " s"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", 
        ... "Wet/Dry: " + string$(wet_dry_percent) + "\%  "
        ... + "  |  Gain: " + fixed$(gain, 2)
        ... + "  |  Fade: " + string$(fade) + " ms"
        ... + "  |  " + speedStr$
        ... + "  |  Render: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"

    Select inner viewport: 0.60, 7.70, 5.12, 5.98
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 6.15
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# Final Info
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", selected$("Sound")

# Play
if play_result
    Play
endif

selectObject: result
